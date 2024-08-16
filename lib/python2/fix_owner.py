#!/usr/local/cpanel/3rdparty/bin/python2
# -*- coding: utf-8 -*-

# cpanel - lib/python2/fix_owner.py                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

"""Change a list owner to a new domain.

This script is intended to be run as a bin/withlist script, i.e.

% bin/withlist -l -r fix_owner listname [options]

Options:
    -n domain
    --newdomain=domain
        (REQUIRED) The new domain of the owner.

    -o domain
    --olddomain=domain
        (REQUIRED) The old domain of the owner.

    -v / --verbose
        Print what the script is doing.

If run standalone, it prints this help text and exits.
"""

import getopt
import re
import sys

import paths
from Mailman import mm_cfg
from Mailman.i18n import C_


def usage(code, msg=''):
    print C_(__doc__.replace('%', '%%'))
    if msg:
        print msg
    sys.exit(code)


def fix_owner(mlist, *args):
    try:
        (opts, args) = getopt.getopt(args, 'n:o:v', ['newdomain=', 'olddomain=', 'verbose'])
    except getopt.error, msg:
        usage(1, msg)

    verbose = 0
    newdomain = olddomain = None
    for (opt, arg) in opts:
        if opt in ('-n', '--newdomain'):
            newdomain = arg
        elif opt in ('-o', '--olddomain'):
            olddomain = arg
        elif opt in ('-v', '--verbose'):
            verbose = 1

    # Make sure list is locked.

    if not mlist.Locked():
        if verbose:
            print C_('Locking list')
        mlist.Lock()

    # Both params are mandatory.

    if not (newdomain and olddomain):
        usage(1, 'A required parameter is missing!')

    owners = mlist.owner
    newowners = list()

    for owner in owners:
        found = re.search(r"\@(([^.]+)\.)?%s$" % olddomain, owner)
        if found:
            owner = re.sub(r"%s$" % re.escape(olddomain), '%s' % newdomain, owner)
        newowners.append(owner)

    if owners != newowners:
        if verbose:
            print C_('Setting owner to: %(newowners)s')
        mlist.owner = newowners

    mlist.Save()
    mlist.Unlock()


if __name__ == '__main__':
    usage(0)
