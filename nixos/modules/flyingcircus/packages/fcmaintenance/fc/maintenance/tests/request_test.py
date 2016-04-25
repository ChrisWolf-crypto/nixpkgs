from fc.maintenance.activity import Activity
from fc.maintenance.request import Request, Attempt
from fc.maintenance.state import State

import datetime
import pytest


def test_duration():
    r = Request(Activity(), 1)
    a = Attempt()
    a.finished = a.started + datetime.timedelta(seconds=10)
    r.attempts.append(a)
    a = Attempt()
    a.finished = a.started + datetime.timedelta(seconds=5)
    r.attempts.append(a)
    assert r.duration == 5  # last attempt counts


def test_save_yaml(tmpdir):
    r = Request(Activity(), 10, 'my comment', dir=str(tmpdir))
    assert r.id is not None
    r.save()
    with open(str(tmpdir / 'request.yaml')) as f:
        assert f.read() == """\
!!python/object:fc.maintenance.request.Request
_reqid: {id}
activity: !!python/object:fc.maintenance.activity.Activity {{}}
attempts: []
comment: my comment
dir: {tmpdir}
estimate: !!python/object:fc.maintenance.estimate.Estimate {{value: 10.0}}
""".format(id=r.id, tmpdir=str(tmpdir))


def test_execute_obeys_retrylimit(tmpdir):
    Request.MAX_RETRIES = 3
    r = Request(Activity(), 1, dir=str(tmpdir))
    results = []
    for i in range(Request.MAX_RETRIES + 1):
        r.execute()
        assert len(r.attempts) == i + 1
        r.update_state()
        results.append(r.state)
    assert results[0] == State.success
    assert results[-2] == State.success
    assert results[-1] == State.retrylimit


class ExternalStateActivity(Activity):

    def load(self):
        with open('external_state') as f:
            self.external = f.read()

    def dump(self):
        with open('external_state', 'w') as f:
            print('foo', file=f)


def test_external_activity_state(tmpdir):
    r = Request(ExternalStateActivity(), 1, dir=str(tmpdir))
    r.save()
    extstate = str(tmpdir / 'external_state')
    with open(extstate) as f:
        assert 'foo\n' == f.read()
    with open(extstate, 'w') as f:
        print('bar', file=f)
    r2 = Request.load(str(tmpdir))
    assert r2.activity.external == 'bar\n'


def test_update_due_should_not_accept_naive_datetimes():
    r = Request(Activity(), 1)
    with pytest.raises(TypeError):
        r.update_due(datetime.datetime(2016, 4, 20, 12, 00))
