#!/usr/bin/env python
# vim: set expandtab shiftwidth=4 fileencoding=UTF-8:

import argparse
import json
import re
import signal
import subprocess
import sys
import types

from os.path import *

# FIXME: The subcommand code in this script is duplicated in several places;
# need to consolidate. (The OpenStack code ships with the "official" version,
# openstack/netronome/subcmd.py).

# Copied directly from subprocess32.py.
# See <https://bugs.python.org/issue1652> and VRT-532.
def _restore_signals():
    signals = ('SIGPIPE', 'SIGXFZ', 'SIGXFSZ')
    for sig in signals:
        if hasattr(signal, sig):
            signal.signal(getattr(signal, sig), signal.SIG_DFL)

vrt532_kwds = {
    'preexec_fn': _restore_signals
}

prog = 'install_deps.py'

class _Subcmd(object):
    def __init__(self, name, description, **kwds):
        super(_Subcmd, self).__init__(**kwds)

        self.name = name
        self.description = description

    def parse_args(self, subcmd, argv):
        parser = argparse.ArgumentParser(
            prog='{} {}'.format(prog, subcmd),
            description=self.description
        )

        parser.add_argument('deps_fname', help='path to JSON dependencies file',
            nargs='+')
        parser.add_argument(
            '--root', '-r', help=
            'root directory for relative paths (default: deps_fname directory)')
        self.add_arguments(parser)

        return parser.parse_args(argv)

    def add_arguments(self, parser):
        pass

class InstallCmd(_Subcmd):
    def __init__(self, **kwds):
        super(InstallCmd, self).__init__(
            name='install',
            description=
            'install packages listed in one or more JSON dependencies files',
            **kwds
        )

    def add_arguments(self, parser):
        parser.add_argument(
            '--dry-run', help='print commands instead of running',
            action='store_true', default=False
        )
        parser.add_argument(
            '--only-if-version-mismatch',
            help="Don't reinstall packages that match already installed "
                 "package versions",
            action='store_true', default=False
        )


    def run(self, subcmd, argv):
        args = self.parse_args(subcmd, argv)

        def action(args, deps, root_dirname):
            self._install_deps(
                deps,
                root_dirname=root_dirname,
                dry_run=args.dry_run,
                check_version=args.only_if_version_mismatch
            )

        _foreach_deps_fname(args, action)


    def _install_deps(self, deps, root_dirname, dry_run, check_version):
        pkgs = []
        for dep in deps:
            for name, pkg in dep.iteritems():
                print >>sys.stdout, name
                sys.stdout.flush()

                if not isabs(pkg):
                    pkg = normpath(join(root_dirname, pkg))

                if check_version and _requested_dep_installed(pkg):
                        msg = pkg + " aready installed, skipping"
                        print >> sys.stdout, msg
                        sys.stdout.flush()
                        continue

                pkgs.append(pkg)

        cmd = ['dpkg', '-i']
        cmd.extend(pkgs)

        if pkgs != []:
            if dry_run:
                print json.dumps(cmd)
            else:
                subprocess.check_call(cmd, **vrt532_kwds)
        else:
            print "All dependencies are already up to date"

class CheckCmd(_Subcmd):
    def __init__(self, **kwds):
        super(CheckCmd, self).__init__(
            name='check',
            description=
            'Checks that the given dependencies are installed',
            **kwds
        )

        self.install_needed = False

    def run(self, subcmd, argv):
        args = self.parse_args(subcmd, argv)

        def action(args, deps, root_dirname):
            self._check_deps(
                deps,
                root_dirname=root_dirname
            )

        _foreach_deps_fname(args, action)

        # Machine-readable command output.
        print 'install' if self.install_needed else 'up-to-date'

    def _check_deps(self, deps, root_dirname):
        for dep in deps:
            for name, pkg in dep.iteritems():
                if not isabs(pkg):
                    pkg = normpath(join(root_dirname, pkg))

                if not _requested_dep_installed(pkg):
                    self.install_needed = True


def _requested_dep_installed(pkg):
    # Get the installed package name and version
    package_name = basename(pkg).split("_")[0]
    cmd = ['dpkg-query', '-s', package_name]
    try:
        installed_pkg = _parse_dpkg(
            subprocess.check_output(cmd, **vrt532_kwds)
        )
    except subprocess.CalledProcessError:
        # The package isn't installed.
        return False

    # Get the .deb package name and version
    cmd = ['dpkg-deb', '-I', pkg]
    requested_pkg = _parse_dpkg(subprocess.check_output(cmd, **vrt532_kwds))

    return 'Version' in installed_pkg.keys() and \
           'Package' in installed_pkg.keys() and \
           (installed_pkg['Package'] == requested_pkg['Package']) and \
           (installed_pkg['Version'] == requested_pkg['Version'])


def _parse_dpkg(input):
    """
    Parses dpkg-deb -I or dpkg-query -s output.
    """

    ans = {}
    for line in input.split('\n'):
        fields = map(lambda x: x.strip(), line.split(':', 1))
        if len(fields) != 2 or ' ' in fields[0]:
            continue
        ans[fields[0]] = fields[1]

    return ans

class VersionsCmd(_Subcmd):
    def __init__(self, **kwds):
        super(VersionsCmd, self).__init__(
            name='versions',
            description=
            'prints versions of installable packages listed in JSON ' \
            'dependencies files',
            **kwds
        )

    def run(self, subcmd, argv):
        args = self.parse_args(subcmd, argv)

        def action(args, deps, root_dirname):
            self._print_versions(deps, root_dirname=root_dirname)

        _foreach_deps_fname(args, action)

    def _print_versions(self, deps, root_dirname):
        for dep in deps:
            for name, pkg in dep.iteritems():
                if not isabs(pkg):
                    pkg = normpath(join(root_dirname, pkg))

                version = self._dpkg_deb_I(pkg)
                print >>sys.stdout, pkg
                print >>sys.stdout, '\t' + version
                sys.stdout.flush()

    def _dpkg_deb_I(self, pkg):
        props = _parse_dpkg(
            subprocess.check_output(['dpkg-deb', '-I', pkg], **vrt532_kwds)
        )

        return props['Version']

def _foreach_deps_fname(args, action):
    for fname in args.deps_fname:
        with open(fname, 'r') as fh:
            deps = json.load(fh)
            if type(deps) == types.DictionaryType:
                deps = [deps]

        if args.root is None:
            root_dirname = dirname(abspath(fname))
        else:
            root_dirname = args.root

        action(args, deps, root_dirname)

class MergeCmd(_Subcmd):
    def __init__(self, **kwds):
        super(MergeCmd, self).__init__(
            name='merge',
            description='merge JSON dependencies files to stdout',
            **kwds
        )

    def add_arguments(self, parser):
        parser.add_argument(
            '--strip-dirnames', help='strip paths to the basename',
            action='store_true', default=False
        )

    def run(self, subcmd, argv):
        args = self.parse_args(subcmd, argv)

        ans = []
        def action(args, deps, root_dirname):
            ans.extend(self._merge(
                deps,
                root_dirname=root_dirname,
                strip_dirnames=args.strip_dirnames
            ))

        _foreach_deps_fname(args, action)

        print json.dumps(ans, indent=4)

    def _merge(self, deps, root_dirname, strip_dirnames):
        ans = []
        for dep in deps:
            dict = {}
            for name, pkg in dep.iteritems():
                if strip_dirnames:
                    pkg = basename(pkg)
                elif not isabs(pkg):
                    pkg = normpath(join(root_dirname, pkg))

                dict[name] = pkg

            ans.append(dict)

        return ans

class PathsCmd(_Subcmd):
    def __init__(self, **kwds):
        super(PathsCmd, self).__init__(
            name='paths',
            description=
            'print full pathnames for packages listed in one or more '
            'JSON dependencies files (for automated builds)',
            **kwds
        )

    def add_arguments(self, parser):
        parser.add_argument(
            '-0', help='NUL-terminate pathnames instead of using newlines',
            action='store_true', default=False, dest='zero'
        )
        parser.add_argument(
            '--strip-dirnames', help='strip paths to the basename',
            action='store_true', default=False
        )

    def run(self, subcmd, argv):
        args = self.parse_args(subcmd, argv)

        def action(args, deps, root_dirname):
            self._print_paths(
                deps,
                root_dirname=root_dirname,
                zero=args.zero,
                strip_dirnames=args.strip_dirnames,
            )

        _foreach_deps_fname(args, action)

    def _print_paths(self, deps, root_dirname, zero, strip_dirnames):
        sep = '\0' if zero else '\n'
        for dep in deps:
            for name, pkg in dep.iteritems():
                if strip_dirnames:
                    pkg = basename(pkg)
                elif not isabs(pkg):
                    pkg = normpath(join(root_dirname, pkg))

                sys.stdout.write(pkg + sep)

class InstallDeps(object):
    def __init__(self, **kwds):
        super(InstallDeps, self).__init__(**kwds)

        self.cmds = [ InstallCmd(), MergeCmd(), PathsCmd(), VersionsCmd(),
                      CheckCmd() ]
        self.cmd_map = {x.name: x for x in self.cmds}

    def usage(self):
        msg = [prog + ' <command> [<args>]', '', 'Known commands:']
        for c in self.cmds:
            msg.append('    {:<15} {}'.format(c.name, c.description))

        return "\n".join(msg)

    def run(self, argv):
        parser = argparse.ArgumentParser(usage=self.usage())
        parser.add_argument('command', help='Subcommand to run')

        args = parser.parse_args(argv[1:2])
        if args.command not in self.cmd_map:
            print >>sys.stderr, \
                'Error: unknown command "{}"'.format(args.command)
            return 2

        return self.cmd_map[args.command].run(
            subcmd=args.command, argv=argv[2:]
        )

if __name__ == "__main__":
    sys.exit(InstallDeps().run(sys.argv))
