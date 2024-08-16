package Cpanel::DB::Reserved;

# cpanel - Cpanel/DB/Reserved.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

sub _list_context_or_die {
    die "List context only!" if !( caller 1 )[5];    #5 for wantarray

    return;
}

sub get_reserved_usernames {
    _list_context_or_die();

    return qw(
      cpldap
      eximstats
      munin
      postgres
      root
      roundcube
    );
}

sub get_reserved_database_names {
    _list_context_or_die();

    return qw(
      cpldap
      eximstats
      information_schema
      munin
      munin_innodb
      mysql
      password
      pg_aggregate
      pg_am
      pg_amop
      pg_amproc
      pg_attrdef
      pg_attribute
      pg_auth_members
      pg_authid
      pg_autovacuum
      pg_cast
      pg_catalog
      pg_class
      pg_constraint
      pg_conversion
      pg_database
      pg_depend
      pg_description
      pg_group
      pg_index
      pg_indexes
      pg_inherits
      pg_language
      pg_largeobject
      pg_listener
      pg_locks
      pg_namespace
      pg_opclass
      pg_operator
      pg_pltemplate
      pg_prepared_xacts
      pg_proc
      pg_rewrite
      pg_roles
      pg_rules
      pg_settings
      pg_shadow
      pg_shdepend
      pg_stat_activity
      pg_stat_all_indexes
      pg_stat_all_tables
      pg_stat_database
      pg_stat_sys_indexes
      pg_stat_sys_tables
      pg_stat_user_indexes
      pg_stat_user_tables
      pg_statio_all_indexes
      pg_statio_all_sequences
      pg_statio_all_tables
      pg_statio_sys_indexes
      pg_statio_sys_sequences
      pg_statio_sys_tables
      pg_statio_user_indexes
      pg_statio_user_sequences
      pg_statio_user_tables
      pg_statistic
      pg_stats
      pg_tables
      pg_tablespace
      pg_trigger
      pg_type
      pg_user
      pg_views
      postgres
      roundcube
      template0
      template1
      test
      whmxfer
    );
}

1;
