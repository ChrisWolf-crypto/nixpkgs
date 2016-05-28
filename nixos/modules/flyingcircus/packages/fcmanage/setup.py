"""fcmanage

High-level system management scripts which are periodiacally called from
a systemd timer: update system configuration from an infrastructure
hydra server or from a local nixpkgs checkout.
"""

from setuptools import setup, find_packages


setup(
    name='fcmanage',
    version='1.0',
    description=__doc__,
    url='https://flyingcircus.io',
    author='Christian Theune, Christian Kauhaus',
    author_email='mail@flyingcircus.io',
    license='ZPL',
    classifiers=[
        'Development Status :: 5 - Production/Stable',
        'Environment :: Console',
        'License :: OSI Approved :: Zope Public License',
        'Programming Language :: Python :: 3.4',
        'Topic :: System :: Systems Administration',
    ],
    packages=find_packages('src'),
    package_dir={'': 'src'},
    install_requires=[
        'fc.maintenance',
        'fc.util',
    ],
    extras_require={
        'test': ['pytest'],
    },
    entry_points={
        'console_scripts': [
            'fc-manage=fcmanage.manage:main',
            'fc-monitor=fcmanage.monitor:main',
            'fc-resize=fcmanage.resize:main',
        ],
    },
)
