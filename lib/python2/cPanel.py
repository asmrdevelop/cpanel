#!/usr/local/cpanel/3rdparty/bin/python2
# -*- coding: utf-8 -*-

# cpanel - lib/python2/cPanel.py                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

import os
import pwd

try:
    import json
except ImportError:
    import simplejson as json

import copy
import logging
import pprint
import tempfile

import cPickle

import sys      # isort:skip
import paths    # isort:skip

# Import this /after/ paths so that the sys.path is properly hacked

from Mailman.i18n import _  # isort:skip

import Mailman.Bouncer      # isort:skip
import Mailman.MailList     # isort:skip

from Mailman.MailList import MailList  # isort:skip
from Mailman import mm_cfg             # isort:skip


# Position 0 is /usr/local/cpanel/lib/python2, so use 1.

sys.path.insert(1, '/usr/local/cpanel/3rdparty/mailman')

#
# The unicode module is broken in some versions of python
# and as a result, it does not load utf-8 as a valid
# encoding which causes convert_unicode_to_utf8 to break
# below with the following error:
#
# LookupError: unknown encoding: utf-8
#
#
# To work around this we just encode a string in utf-8 right
# away and it all works now.
#

u = ''
u.encode('utf-8')
u = ''
u.encode('iso-8859-1')


def drop_privileges_to(username):
    pw = pwd.getpwnam(username)
    (uid, gid) = (pw[2], pw[3])
    drop_privileges_to_uid_gid(uid, gid)


def drop_privileges_to_uid_gid(uid, gid):
    try:
        os.setgroups([gid])
    except:
        pass
    os.setgid(gid)
    os.setegid(gid)
    os.setuid(uid)
    os.seteuid(uid)


def update_mailman(list, func):
    drop_privileges_to('mailman')

    mlist = MailList(list, lock=0)

    dict_copy = copy.copy(mlist.__dict__)

    # Only the owner is deep copied because
    # deepcopy was causing a loop of
    # Exception RuntimeError: 'maximum recursion depth exceeded while calling a Python object'

    dict_copy['owner'] = copy.deepcopy(mlist.__dict__['owner'])

    func(dict_copy)

    if dict_copy != mlist.__dict__:
        mlist.Lock()

        func(mlist.__dict__)

        try:
            mlist.Save()
        finally:
            mlist.Unlock()


def export_cpanel_pickle_keys_as_json(filenames, sysuser, max_pickle_file_size):
    cpanelkeys = {
        'advertised': 1,
        'archive_private': 1,
        'private_roster': 1,
        'subscribe_policy': 1,
        'owner': 1,
        }

    all_config_files = filenames.split(',')

    results = ''
    for filename in all_config_files:
        try:
            results += export_pickle_as_json(filename, sysuser, max_pickle_file_size, cpanelkeys) + '\n'
        except Exception, e:
            results += '\n'
            logging.exception('Failed to load ' + filename + ' and output JSON')

    results = results.rstrip('\n')

    return results


def export_pickle_as_json(
    filename,
    sysuser,
    max_pickle_file_size,
    wantkeys={},
    ):

    fh = open(filename, 'r')
    fhstat = os.fstat(fh.fileno())
    if fhstat.st_size > max_pickle_file_size:
        raise Exception('export_pickle_as_json attempted to load a file larger than %d' % max_pickle_file_size)

    tmpdir = tempfile.mkdtemp('', '')

    (pipein, pipeout) = os.pipe()
    newpid = os.fork()
    if newpid == 0:
        os.close(pipein)
        os.write(pipeout, export_pickle_as_json_child(tmpdir, fh, sysuser, wantkeys))
        os.close(pipeout)
        os._exit(0)
    else:
        fh.close()
        os.close(pipeout)
        json = ''
        while True:
            buff = os.read(pipein, 32768)
            json += buff
            if not len(buff):
                break

        os.close(pipein)
        os.waitpid(newpid, 0)
        os.rmdir(tmpdir)

        if len(json) == 0:
            raise Exception('export_pickle_as_json_child failed to produce JSON output')

        return json


def mailman_imports_only(mod_name, kls_name):
    if mod_name == 'Mailman.UserDesc':
        mod_obj = __import__(mod_name, {}, {}, ['Mailman'])
        return getattr(mod_obj, kls_name)
    elif mod_name == 'Mailman.Bouncer':
        mod_obj = __import__(mod_name, {}, {}, ['Mailman'])
        return getattr(mod_obj, kls_name)
    else:
        raise Exception('Cannot import unsupported module: ' + mod_name + ' with class name: ' + kls_name)


def export_pickle_as_json_child(
    tmpdir,
    fh,
    sysuser,
    wantkeys,
    ):

    pw = pwd.getpwnam(sysuser)
    (uid, gid) = (pw[2], pw[3])

    os.chroot(tmpdir)

    drop_privileges_to_uid_gid(uid, gid)

    unpickler = cPickle.Unpickler(fh)
    unpickler.find_global = mailman_imports_only

    dict = {}
    dict = unpickler.load()

    # Reset the Bouncer object

    if dict.has_key('bounce_info'):
        dict['bounce_info'] = {}

    if dict.has_key('evictions'):
        evictions = dict['evictions']
        for cookie in evictions.keys():
            del dict[cookie]
            del evictions[cookie]

 # If they only want specific keys
 # create a new dictionary with just
 # the keys we need.
 #
 # Currently only used by
 # dump_cpanel_mailmancfg_as_json to just
 # export the keys in def export_cpanel_pickle_keys_as_json

    if wantkeys.items():
        limited_dict = {}
        for (k, v) in wantkeys.items():
            limited_dict[k] = dict[k]
        dict = limited_dict

    dict = convert_tuples(dict)

    fh.close()

    try:
        return json.dumps(convert_unicode_to_utf8(dict), encoding='utf-8', ensure_ascii=False)
    except:
        print 'Failed to export to json'
        pp = pprint.PrettyPrinter(indent=4)
        pp.pprint(dict)
        raise


#
#  json.loads converts all the strings to unicode objects
#  which breaks cPickle.dump.  We have to convert them back
#  to utf-8 strings to avoid mailman trying to convert the unicode
#  objects to unicode later (it does not know they are already unicode)
#

def json_to_pickle(jsonstr):

    # Ensure all utf8 is in unicode for
    # pickle

    dict = downgrade_unicode_if_possible(json.loads(jsonstr, object_hook=json_convert_stringified_int_keys_to_ints))
    dict = restore_tuples(dict)

    # Use pickle protocol 2, which is the highest supported by Python 2.4
    # (CentOS 5).

    return cPickle.dumps(dict, 2)


def is_int(input):
    try:
        num = int(input)
    except ValueError:
        return False
    return True


def json_convert_stringified_int_keys_to_ints(the_dict):
    if isinstance(the_dict, dict):
        return dict([((int(key) if is_int(key) else key), value) for (key, value) in the_dict.items()])
    return the_dict


def convert_unicode_to_utf8(input, is_value=False):
    if isinstance(input, dict):
        return dict([(convert_unicode_to_utf8(key), convert_unicode_to_utf8(value, True)) for (key, value) in input.iteritems()])
    elif isinstance(input, list):
        return [convert_unicode_to_utf8(element) for element in input]
    elif isinstance(input, unicode):
        return input.encode('utf-8')
    elif isinstance(input, str):
        s = input.decode('iso-8859-1').encode('utf-8')
        if not is_value:
            return s
        return {'__bytestring__': True, '__string__': s}
    else:
        return input


def downgrade_unicode_if_possible(input):
    if isinstance(input, dict):
        return dict([(downgrade_unicode_if_possible(key), downgrade_unicode_if_possible(value)) for (key, value) in input.iteritems()])
    elif isinstance(input, list):
        return [downgrade_unicode_if_possible(element) for element in input]
    elif isinstance(input, unicode):
        try:
            return input.encode('ascii')
        except:
            return input
    else:
        return input


def restore_tuples(value):
    if isinstance(value, dict):
        try:
            if len(value['__items__']) == value['__tuple__'] and len(value.keys()) == 2:
                return restore_tuples(tuple(value['__items__']))
        except:
            pass
        try:
            if value['__bytestring__'] is True and len(value.keys()) == 2:
                return value['__string__'].encode('iso-8859-1')
        except:
            pass
        return dict([(restore_tuples(k), restore_tuples(v)) for (k, v) in value.iteritems()])
    elif isinstance(value, list):
        return [restore_tuples(element) for element in value]
    elif isinstance(value, tuple):
        return tuple([restore_tuples(element) for element in value])
    else:
        return value


def convert_tuples(value):
    if isinstance(value, dict):
        return dict([(convert_tuples(k), convert_tuples(v)) for (k, v) in value.iteritems()])
    elif isinstance(value, list):
        return [convert_tuples(element) for element in value]
    elif isinstance(value, tuple):
        value = [convert_tuples(element) for element in value]
        return {'__tuple__': len(value), '__items__': value}
    else:
        return value


def get_mailman_pickle(list):
    return '/usr/local/cpanel/3rdparty/mailman/lists/%s/config.pck' % list


def mailman_url_for_domain(domain):
    if hasattr(mm_cfg, 'DEFAULT_URL_PATTERN') and len(mm_cfg.DEFAULT_URL_PATTERN) > 0:
        return mm_cfg.DEFAULT_URL_PATTERN % domain
    else:
        return 'http://' + domain + '/mailman'


