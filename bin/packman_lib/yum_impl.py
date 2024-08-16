# -*- coding: utf-8 -*-

# cpanel - bin/packman_lib/yum_impl.py             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

import json
import re
import types

import yum
from yum.packageSack import packagesNewestByName

__all__ = "init_yum get_info_for_packages_and_prefixes get_info_for_single_package output_json doPackageLists".split()

yb = None  # type: yum.YumBase

cache = {
    "whatProvides": {},
    "NewestByName": {},
    "packageStates": {},
    "returnNewestByName": {},
}

# Work around yum (3.4?) bug where yb._compare_providers() would
#     erroneously fail, when the "installed" psuedo-repo was involved, with:
#         AttributeError: FakeRepository instance has no attribute 'getClass'

if not hasattr(yum.packages.FakeRepository, "compare_providers_priority"):
    yum.packages.FakeRepository.compare_providers_priority = 99


class FastYumBase(yum.YumBase):
    """A wrapper around YumBase to cache lookups."""

    def _getSacks(self, *args, **kwargs):
        """wrap yum.YumBase._getSacks"""
        global cache

        if self._pkgSack is not None and kwargs.get("thisrepo") is None:
            return self._pkgSack

        pkgSack = super(FastYumBase, self)._getSacks(*args, **kwargs)

        # Overload the returnNewestByName function in the pkgSack
        # module so we can avoid looking up packages that we already have
        orig_returnNewestByName = pkgSack.returnNewestByName
        newest_by_name_cache = cache["returnNewestByName"]

        def new_returnNewestByName(self, pkg_tup):
            if pkg_tup not in newest_by_name_cache:
                newest_by_name_cache[pkg_tup] = orig_returnNewestByName(pkg_tup)

            return newest_by_name_cache[pkg_tup]

        pkgSack.returnNewestByName = types.MethodType(new_returnNewestByName, pkgSack)

        return pkgSack


def init_yum(disable_excludes=False):
    global yb
    global cache
    yb = FastYumBase()

    # Disable the fastestmirror plugin as it is
    # multithreaded by default, and causes issues when packman
    # invoked via cpsrvd (i.e., via the WHM UI).
    yb.preconf.disabled_plugins = ["fastestmirror"]
    yb.preconf.init_plugins = False

    if hasattr(yb, "setCacheDir"):
        yb.setCacheDir()
    if disable_excludes:
        yb.conf.disable_excludes = {"all": 1}

    yb.repos.populateSack()


def _get_what_provides(pkg, ver_op, ver_dat):
    global cache
    cache_key = (pkg, str(ver_op), str(ver_dat))
    wp_cache = cache["whatProvides"]

    if cache_key in wp_cache:
        return wp_cache[cache_key]

    quick_pkg = pkg

    # If its a package and it provides what we want we can
    # skip yb.whatProvides

    if quick_pkg.count("(") == 1:
        # Strip (x86-64), (noarch), (i386)
        # since we only care about package names

        quick_pkg = re.sub("\((?:x86-64|noarch|i386|i586|i686)\)", "", quick_pkg)

    if (
        quick_pkg.count("(") == 0 and quick_pkg.count("/") == 0
    ):  # Ignore /bin/bash and rpmlib(PayloadIsXz)
        package_obj = _get_package_obj(quick_pkg)
        if package_obj != None:
            yb._last_req = package_obj
            if yb._quickWhatProvides(quick_pkg, ver_op, ver_dat):
                wp_cache[cache_key] = [package_obj]
                return wp_cache[cache_key]

    wp_cache[cache_key] = []
    providers = yb.whatProvides(pkg, ver_op, ver_dat)

    # Find the latest version of each package only
    # since we never install old versions of a package

    seen_pkg = {}
    for prov_pkg in providers:
        if seen_pkg.get(prov_pkg.name):
            continue
        seen_pkg[prov_pkg.name] = 1
        newestPkg = _get_package_obj(prov_pkg.name)
        if newestPkg:
            wp_cache[cache_key].append(newestPkg)

    return wp_cache[cache_key]


def _get_package_obj(package_name):
    global cache
    if package_name in cache["NewestByName"]:
        return cache["NewestByName"][package_name]

    try:
        package_obj = yb.pkgSack.returnNewestByName(package_name)[0]
    except yum.Errors.PackageSackError:
        package_obj = None

    cache["NewestByName"][package_name] = package_obj
    return package_obj


def _load_package_info_into_cache_for_packages_and_prefixes(pkglist=[], prefixes=[]):
    global cache
    wanted_patterns = pkglist
    for prefix in prefixes:
        wanted_patterns.append(prefix + "*")

    # Passing in the repoid saves another 200ms but it does not seem
    # to work on cent6
    # ygh = yb.doPackageLists(pkgnarrow='all', repoid='EA4', patterns=wanted_patterns)

    ygh = yb.doPackageLists(pkgnarrow="all", patterns=wanted_patterns)
    installedPkgs = ygh.installed
    availablePkgs = ygh.available

    # ygh = yb.doPackageLists(pkgnarrow='updates', patterns=wanted_patterns)
    # updatePkgs = ygh.updates

    _create_pkg_map_and_package_name_to_possible_objs(
        {"available": availablePkgs, "installed": installedPkgs}
    )  # , 'updates': updatePkgs})


def _create_pkg_map_and_package_name_to_possible_objs(ygh):
    global cache

    cache_NewestByName = cache["NewestByName"]
    cache_packageStates = cache["packageStates"]

    all_packages_by_name = {}
    installed_packages_by_name = {}

    for pkg_list in ["available", "installed"]:
        for pkg in ygh[pkg_list]:
            if pkg_list == "installed":
                installed_packages_by_name[pkg.name] = pkg
            all_packages_by_name.setdefault(pkg.name, []).append(pkg)

    for package_name in all_packages_by_name:
        cache_NewestByName[package_name] = packagesNewestByName(
            all_packages_by_name[package_name]
        )[0]
        pkg_dict = cache_packageStates[package_name] = {}
        pkg_dict["version_latest"] = (
            cache_NewestByName[package_name].version
            + "-"
            + cache_NewestByName[package_name].release
        )
        if package_name in installed_packages_by_name:
            pkg = installed_packages_by_name[package_name]
            pkg_dict["version_installed"] = pkg.version + "-" + pkg.release
            if pkg_dict["version_latest"] != pkg_dict["version_installed"]:
                pkg_dict["state"] = "updatable"
            else:
                pkg_dict["state"] = "installed"
        else:
            pkg_dict["state"] = "available"

    return 1


def _get_pkg_info(package_name, populate_provides=True):
    global cache
    pkg_dict = dict()

    package_obj = _get_package_obj(package_name)
    if package_obj == None:
        return

    pkg_out = dict()
    pkg_out["name"] = package_obj.name
    pkg_out["arch"] = package_obj.arch
    pkg_out["size_installed"] = package_obj.installedsize
    pkg_out["release"] = package_obj.release
    pkg_out["version"] = package_obj.version
    pkg_out["summary"] = package_obj.summary
    pkg_out["description"] = package_obj.description
    pkg_out["url"] = package_obj.url
    pkg_out["rpm_license"] = package_obj.license
    pkg_out["deplist"] = []
    pkg_out["conflicts"] = []
    pkg_out["pkg_group"] = package_obj.group

    packageStates = cache["packageStates"][package_name]

    # store the installed and latest versions

    pkg_out["_state"] = packageStates["state"]
    pkg_out["_installed"] = packageStates.get("version_installed", "")
    pkg_out["_latest"] = packageStates.get("version_latest", "")

    # turn non-package requires/conflicts into the package that provides it if possible
    if populate_provides:
        _populate_provides_for("requires", pkg_out, package_obj)
        _populate_provides_for("conflicts", pkg_out, package_obj)

    return pkg_out


def _populate_provides_for(type_key, pkg_out, package_obj):
    if type_key != "requires" and type_key != "conflicts":
        raise ValueError("first arg must be 'requires' or 'conflicts'")

    target_key = "deplist" if type_key == "requires" else "conflicts"

    for pkg_dat in getattr(package_obj, type_key):
        (pkg, ver_op, ver_dat) = pkg_dat

        try:
            pkg_lst = _get_what_provides(pkg, ver_op, ver_dat)

            # If there is more then one package that can provide
            # what we are looking for we need to sort them

            if len(pkg_lst) > 1:
                sorted_pkg_list = yb._compare_providers(pkg_lst, package_obj)
                pkg_lst = []
                for pkg_with_score in sorted_pkg_list:
                    pkg_lst.append(pkg_with_score[0])

            provided_by = []
        except ValueError:
            pkg_obj = None
            pkg_lst = []
            provided_by = []

        for prov_pkg in pkg_lst:
            provided_by.append([prov_pkg.name, prov_pkg.version, prov_pkg.release])

        pkg_out[target_key].append({"name": pkg, "provided_by": provided_by})


def get_info_for_packages_and_prefixes(pkglist, prefixes=[], populate_provides=True):
    global cache
    _load_package_info_into_cache_for_packages_and_prefixes(pkglist, prefixes)
    response = []

    cache_packageStates = cache["packageStates"]
    for pkg in cache_packageStates:
        response.append(_get_pkg_info(pkg, populate_provides=populate_provides))

    return response


def get_info_for_single_package(package_name, populate_provides=True):
    try:
        return get_info_for_packages_and_prefixes(
            [package_name], populate_provides=populate_provides
        )[0]
    except IndexError:
        return


def output_json(response):
    # We print the header before the JSON
    # because the yum libraries will have
    # printed some text of their own.

    print "JSON_OUTPUT_HEADER"
    try:
        print json.dumps(response)
    except AttributeError:

        # older json module has different interface

        print json.write(response)


def doPackageLists(pkgnarrow="all", patterns=None):
    return yb.doPackageLists(pkgnarrow, patterns)
