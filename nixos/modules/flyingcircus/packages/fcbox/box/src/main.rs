#[macro_use]
extern crate clap;
#[macro_use]
extern crate error_chain;
extern crate users;
extern crate libc;
extern crate walkdir;
extern crate errno;

use std::ffi::CString;
use std::io::{self, Write, stderr};
use std::os::unix::ffi::OsStrExt;
use std::path::{Path, PathBuf, MAIN_SEPARATOR};
use users::os::unix::GroupExt;
use users::{User, gid_t, Users, UsersCache, Groups};
use walkdir::WalkDir;

mod test;

// must be kept in sync with ids.gids in n/m/flyingcircus/static/default.nix
const USERS: gid_t = 100;
const SERVICE: gid_t = 900;

#[cfg(not(test))]
static PREFIX: &'static str = "/mnt/auto/box";

#[cfg(test)]
static PREFIX: &'static str = "/tmp";


mod errors {
    use errno::Errno;

    error_chain!{
        foreign_links {
            Io(::std::io::Error);
            WalkDir(::walkdir::Error);
            NulError(::std::ffi::NulError);
        }

        errors {
            Declined(msg: String) {
                description("Trying to do something which is against the policy")
                display("Sorry, Dave. I'm afraid I can't do that.\n\
                         {}", msg)
            }

            GrantUser(msg: String) {
                description("The grant target user in invalid")
                display("Too bad, I cannot grant this box to the specified user.\n\
                         {}", msg)
            }

            OSErr(errno: Errno) {
                description("OS error")
                display("Operation failed: {}", errno)
            }
        }
    }

}

use errors::*;

macro_rules! declined {
    ($($tt:tt)*) => {
        Err(ErrorKind::Declined(format!($($tt)*)).into());
    }
}


fn myprefix<U: Users>(usercache: &U) -> Result<PathBuf> {
    let mut p = PathBuf::from(PREFIX);
    match usercache.get_current_username() {
        Some(u) => p.push(u.as_ref()),
        None => bail!("Failed to determine my own user name. Everything alright?"),
    };
    Ok(p)
}

fn expand(boxdir: &Path, prefix: &Path) -> PathBuf {
    if boxdir.to_string_lossy().contains(MAIN_SEPARATOR) {
        boxdir.to_path_buf()
    } else {
        prefix.join(boxdir)
    }
}

fn below_prefix(boxdir: &Path, prefix: &Path) -> bool {
    let mut cand = boxdir.clone();
    while cand.parent().is_some() {
        // identify the part that actually exists
        if let Ok(p) = cand.canonicalize() {
            return p.starts_with(prefix);
        }
        cand = cand.parent().unwrap();
    }
    false
}

fn drop_fsprivs<F>(unprivileged_code: F) -> io::Result<()>
    where F: Fn() -> io::Result<()>
{
    let saved_uid = unsafe { libc::geteuid() };
    unsafe {
        libc::setfsuid(libc::getuid());
    }
    let res = unprivileged_code();
    unsafe {
        libc::setfsuid(saved_uid);
    }
    res
}

fn createbox(path: &Path) -> Result<()> {
    println!("Creating box directory `{}'.", path.display());
    drop_fsprivs(|| std::fs::create_dir(path)).chain_err(|| {
            format!("No luck while creating box dir `{}'", path.display())
        })?;
    Ok(())
}

fn chmod(path: &Path, mode: libc::mode_t) -> Result<()> {
    let c_path = CString::new(path.as_os_str().as_bytes())?;
    match unsafe { libc::chmod(c_path.as_ptr(), mode) } {
        0 => Ok(()),
        _ => Err(ErrorKind::OSErr(errno::errno()).into()),
    }
}

#[cfg(not(test))]
fn chown(path: &Path, user: &User, gid: gid_t) -> Result<()> {
    let c_path = CString::new(path.as_os_str().as_bytes())?;
    match unsafe { libc::chown(c_path.as_ptr(), user.uid(), gid) } {
        0 => Ok(()),
        _ => Err(ErrorKind::OSErr(errno::errno()).into()),
    }
}

#[cfg(test)]
fn chown(_: &Path, _: &User, _: gid_t) -> Result<()> {
    Ok(())
}

fn chown_recursive(boxdir: &Path, user: &User, gid: gid_t) -> Result<()> {
    for entry in WalkDir::new(boxdir) {
        let entry = entry?;
        if let Err(e) = chown(entry.path(), user, gid) {
            writeln!(stderr(),
                     "{}: Warning while changing ownership of `{}' to `{}': {}",
                     crate_name!(),
                     entry.path().display(),
                     user.name(),
                     e)?;
        };
    }
    Ok(())
}

fn make_public(boxdir: &Path, realuser: &User) -> Result<()> {
    chown_recursive(boxdir, realuser, USERS)?;
    chmod(boxdir, 0o755)
}

fn make_private(boxdir: &Path, realuser: &User) -> Result<()> {
    chown_recursive(boxdir, realuser, USERS)?;
    chmod(boxdir, 0o700)
}

fn grant<U: Users>(boxdir: &Path, touser: &str, usercache: &U) -> Result<()> {
    match usercache.get_user_by_name(touser) {
        Some(ref user) if user.primary_group_id() == SERVICE => {
            chown_recursive(&boxdir, user, SERVICE)
        }
        Some(_) => {
            Err(ErrorKind::GrantUser(format!("Cannot give files away to non-serviceuser {}",
                                             touser))
                .into())
        }
        None => Err(ErrorKind::GrantUser(format!("User {} not found", touser)).into()),
    }
}

fn authorized<U: Users + Groups>(me: &User, users: &U) -> bool {
    if me.primary_group_id() != USERS {
        return false;
    };
    match users.get_group_by_name("sudo-srv")
        .and_then(|g| Some(g.members().iter().any(|ref username| username == &me.name()))) {
        Some(found) => found,
        None => false,
    }
}

fn run<U: Users + Groups>(touser: &str, boxdir: &Path, users: &U) -> Result<()> {
    let realuser = users.get_user_by_uid(users.get_current_uid())
        .ok_or(Error::from(format!("failed to look up current user id {}",
                                   users.get_current_uid())))?;
    if !authorized(&realuser, users) {
        return declined!("Only human users with `sude-srv' permission are allowed to use me");
    }

    let myprefix = myprefix(users)?;
    let expbox = expand(boxdir, &myprefix);
    if !below_prefix(&expbox, &myprefix) {
        return declined!("You can only manage boxes in `{}'.", myprefix.display());
    }
    if !expbox.exists() {
        createbox(&expbox)?;
    }

    let canonical = expbox.canonicalize()?;
    if !canonical.is_dir() {
        let msg = format!("You can only manage directories. `{}' isn\'t one.",
                          canonical.display());
        return Err(ErrorKind::Declined(msg).into());
    }
    match touser {
        "public" => make_public(&canonical, &realuser),
        "private" => make_private(&canonical, &realuser),
        _ => grant(&canonical, touser, users),
    }
}

fn main() {
    let mut app = clap_app!(
        box =>
        (version: crate_version!())
        (about: crate_description!())
        (@subcommand grant =>
         (about: "Manages access permissions for box directories")
         (@arg USER: * "User to grant permission to. Can be a service user available on this \
                        machine, or \"public\", or \"private\"")
         (@arg BOXDIR: * "Directory inside ~/box. Will be created if it doesn't exist")
        )
        );
    let m = app.clone().get_matches();
    match m.subcommand_matches("grant") {
        Some(g) => {
            let mut users = UsersCache::new();
            let boxdir = Path::new(g.value_of("BOXDIR").unwrap());
            if let Err(ref e) = run(g.value_of("USER").unwrap(), boxdir, &mut users) {
                writeln!(stderr(), "Error: {}", e).unwrap();
                for e in e.iter().skip(1) {
                    writeln!(stderr(), "Cause: {}", e).unwrap();
                }
                std::process::exit(1);
            }
        }
        None => app.print_long_help().unwrap_or_else(|e| e.exit()),
    }
}
