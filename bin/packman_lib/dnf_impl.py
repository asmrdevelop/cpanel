# -*- coding: utf-8 -*-

# cpanel - bin/packman_lib/dnf_impl.py             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
import json
import sys

__all__ = "init_yum get_info_for_packages_and_prefixes get_info_for_single_package output_json doPackageLists".split()

import dnf

base = None  # type: dnf.Base

cache = {
    "whatProvides": {},
    "NewestByName": {},
    "packageStates": {},
    "returnNewestByName": {},
}


def init_yum(disable_excludes=False):
    global base
    global cache

    base = dnf.Base()
    conf = base.conf
    conf.read()

    #### from /usr/lib/python3.6/site-packages/dnf/cli/cli.py ##
    # search reposdir file inside the installroot first
    from_root = conf._search_inside_installroot("reposdir")
    # Update vars from same root like repos were taken
    if conf._get_priority("varsdir") == dnf.conf.PRIO_COMMANDLINE:
        from_root = "/"
    subst = conf.substitutions
    subst.update_from_etc(from_root, varsdir=conf._get_value("varsdir"))
    #### /from /usr/lib/python3.6/site-packages/dnf/cli/cli.py ##

    if disable_excludes:
        conf.disable_excludes += ["all"]

    base.read_all_repos()
    base.fill_sack(load_system_repo=True, load_available_repos=True)


def _get_package_obj(package_name):
    global cache
    if package_name in cache["NewestByName"]:
        return cache["NewestByName"][package_name]

    try:
        package_obj = base.sack.query().filter(name=package_name).latest()[0]
    except Exception:
        package_obj = None

    cache["NewestByName"][package_name] = package_obj
    return package_obj


def _load_package_info_into_cache_for_packages_and_prefixes(pkglist=[], prefixes=[]):
    global cache
    wanted_patterns = pkglist
    for prefix in prefixes:
        wanted_patterns.append(prefix + "*")

    ygh = doPackageLists(pkgnarrow="all", patterns=wanted_patterns)
    installedPkgs = ygh.installed
    availablePkgs = ygh.available

    _create_pkg_map_and_package_name_to_possible_objs(
        {"available": availablePkgs, "installed": installedPkgs}
    )


def _take_newest(pkgs):
    newest = None
    for pkg in pkgs:
        if "src" == pkg.arch:
            continue

        if not newest:
            newest = pkg
            continue

        pkg_is_newer = newest.evr_cmp(pkg) < 0
        if pkg_is_newer:
            newest = pkg

    return newest


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
            if pkg.name not in all_packages_by_name:
                all_packages_by_name[pkg.name] = []
            all_packages_by_name[pkg.name].append(pkg)

    for package_name in all_packages_by_name:
        cache_NewestByName[package_name] = _take_newest(
            all_packages_by_name[package_name]
        )
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

    package_obj = _get_package_obj(package_name)
    if package_obj == None:
        return

    pkg_out = dict()
    pkg_out["name"] = package_obj.name
    pkg_out["arch"] = package_obj.arch
    pkg_out["size_installed"] = package_obj.installsize
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

    reldeps = getattr(package_obj, type_key)

    for reldep in reldeps:
        # the Reldep class only exposes a __str__ method and that string represents an expression.
        # rpm/dnf now supports boolean dependencies; for example, Requires: (enchant or enchant2)
        # so it is not possible to return a single "name" for such deps. Let's try stuffing the whole
        # expression into the name key.
        # http://rpm.org/user_doc/boolean_dependencies.html
        pkg = str(reldep)

        provided_by = []
        seen = dict()
        # todo not sure how to sort multiple providers; cannot find an equivalent for _compare_providers
        # see https://webpros.atlassian.net/browse/ZC-7055
        for provider in base.sack.query().filter(provides=reldep).latest():
            if provider.name in seen:
                continue
            provided_by.append([provider.name, provider.version, provider.release])
            seen[provider.name] = True

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
    # We print the header before the JSON because client programs expect it.
    print("JSON_OUTPUT_HEADER")
    json.dump(response, fp=sys.stdout)


def doPackageLists(
    pkgnarrow="all", patterns=None, showdups=None, ignore_case=False, repoid=None
):
    # dnf looks for 'upgrades' but returns 'updates'
    if "updates" == pkgnarrow:
        pkgnarrow = "upgrades"

    return base._do_package_lists(pkgnarrow, patterns, showdups, ignore_case, repoid)
