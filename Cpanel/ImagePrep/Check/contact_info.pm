
# cpanel - Cpanel/ImagePrep/Check/contact_info.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::ImagePrep::Check::contact_info;

use cPstrict;
use parent 'Cpanel::ImagePrep::Check';

use Cpanel::Config::LoadWwwAcctConf ();

=head1 NAME

Cpanel::ImagePrep::Check::contact_info - A subclass of C<Cpanel::ImagePrep::Check>.

=cut

sub _description {
    return <<~"EO_DESC";
        Check for configured server contacts.
        EO_DESC
}

sub _check ($self) {
    my $wwwacct_hr = Cpanel::Config::LoadWwwAcctConf::loadwwwacctconf();

    # Ignore CONTACTEMAIL, CONTACTPAGER
    if ( my @unwanted = sort grep { /^(?:CONTACT(?!EMAIL|PAGER)|ICQ)/ && length $wwwacct_hr->{$_} } keys %{$wwwacct_hr} ) {
        die <<~"EO_DIE";
            There are one or more configured contacts found in '/etc/wwwacct.conf' or '/etc/wwwacct.conf.shadow'. This is not a supported configuration for template VMs.

            Configured contacts:
            @{[join "\n", map { "  - $_" } @unwanted]}
            EO_DIE
    }
    else {
        $self->loginfo('No contact configuration.');
    }

    return;
}

1;
