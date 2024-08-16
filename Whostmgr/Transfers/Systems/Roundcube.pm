package Whostmgr::Transfers::Systems::Roundcube;

# cpanel - Whostmgr/Transfers/Systems/Roundcube.pm Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

# RR Audit: JNK
use base qw(
  Whostmgr::Transfers::SystemsBase::MysqlBase
);

use Try::Tiny;

use Cpanel::Autodie            ();
use Cpanel::Config::LoadCpConf ();

# Logic for sqlite and mysql are broken into their own modules for
# easier testing
use Whostmgr::Transfers::Systems::Roundcube::mysql  ();    # PPI NO PARSE - lies
use Whostmgr::Transfers::Systems::Roundcube::sqlite ();    # PPI NO PARSE - lies

sub get_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext('This restores [asis,Roundcube] configuration and preferences.') ];
}

sub get_restricted_available {
    return 1;
}

# CPANEL-15457: Ensure Roundcube restore occurs before MySQL, since the way we restore Roundcube permanently
# resets the cpuser's MySQL password with a "temporary" password.
sub get_phase {
    return 35;
}

sub _get_source_roundcube_type {
    my ($self) = @_;
    my $sql_file = $self->_archive_mysql_dir() . "/roundcube.sql";

    return Cpanel::Autodie::exists($sql_file) ? 'mysql' : 'sqlite';
}

sub restricted_restore {
    my ($self) = @_;

    my $cpconf_ref = Cpanel::Config::LoadCpConf::loadcpconf();
    my $rcube_db   = $self->_get_source_roundcube_type();
    my $ns         = "Whostmgr::Transfers::Systems::Roundcube::$rcube_db";
    my $sub;
    try { $sub = $ns->can('do_restore'); };
    if ( !$sub ) {
        $self->{'_utils'}->add_skipped_item("$rcube_db roundcube restore is not implented.");
        return 1;
    }
    return $sub->( $self, $cpconf_ref );
}

*unrestricted_restore = \&restricted_restore;

1;
