package Cpanel::Install::Job::SSHDUseDNS;

# cpanel - Cpanel/Install/Job/SSHDUseDNS.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Install::Job::SSHDUseDNS

=head1 DESCRIPTION

This module disables SSHD’s C<UseDNS> setting, which
interacts poorly with cPHulk.

=cut

#----------------------------------------------------------------------

use parent qw( Cpanel::Install::Job );

use Cpanel::Imports;

use Cpanel::LocaleString            ();    ## PPI USE OK - cplint is wrong
use Whostmgr::Services::SSH::UseDNS ();

#----------------------------------------------------------------------

use constant _DESCRIPTION => Cpanel::LocaleString->new( 'Ensuring that [asis,SSHD]’s “[_1]” setting is disabled …', 'UseDNS' );

sub _run ($self) {

    if ( Whostmgr::Services::SSH::UseDNS::disable_if_needed() ) {
        $self->_logger()->info( locale()->maketext( '[asis,SSHD]’s “[_1]” setting is now disabled. The system will now restart [asis,SSHD] to make the changes take effect.', 'UseDNS' ) );
    }
    else {
        $self->_logger()->info( locale()->maketext('No action was necessary.') );
    }

    return;
}

1;
