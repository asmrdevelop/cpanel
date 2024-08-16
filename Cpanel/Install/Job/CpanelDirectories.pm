package Cpanel::Install::Job::CpanelDirectories;

# cpanel - Cpanel/Install/Job/CpanelDirectories.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Install::Job::CpanelDirectories

=head1 DESCRIPTION

This module creates needed direectories.

=cut

#----------------------------------------------------------------------

use parent qw( Cpanel::Install::Job );

use Cpanel::Imports;
use Cpanel::Autodie qw(mkdir_if_not_exists chmod);

use Cpanel::LocaleString ();    ## PPI USE OK - cplint is wrong

#----------------------------------------------------------------------

use constant _DESCRIPTION => Cpanel::LocaleString->new( 'Creating directories for [asis,cPanel amp() WHM] …', '' );

our %DIR_PERMS;

BEGIN {
    %DIR_PERMS = (
        '/var/cpanel'         => 0711,
        '/var/cpanel/version' => 0755,
    );
}

sub _run ($self) {
    local $@;

    foreach my $d ( sort keys %DIR_PERMS ) {
        my $perms = $DIR_PERMS{$d};

        $self->_logger()->info( locale()->maketext( 'Creating “[_1]” …', $d ) );

        $self->_logger()->error("$@") if !eval {
            Cpanel::Autodie::mkdir_if_not_exists( $d, $perms ) or do {
                my $indent = $self->_logger()->create_log_level_indent();

                $self->_logger()->info( locale()->maketext( '“[_1]” already exists. Ensuring the correct permissions …', $d ) );

                Cpanel::Autodie::chmod( $perms, $d );
            };

            1;
        };
    }

    return;
}

1;
