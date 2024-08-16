package Whostmgr::API::1::Wwwacct;

# cpanel - Whostmgr/API/1/Wwwacct.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::LoadWwwAcctConf ();
use Cpanel::Config::SaveWwwAcctConf ();
use Cpanel::Locale                  ();
use Cpanel::Validate::EmailRFC      ();
use Cpanel::Validate::NameServer    ();
use Whostmgr::API::1::Utils         ();

use constant NEEDS_ROLE => {
    update_nameservers_config => undef,
    update_contact_email      => undef,
};

=encoding utf-8

=head1 NAME

Whostmgr::API::1::Wwwacct - WHM API functions to manage server configurations
in /etc/wwwacct.conf.

=head1 SUBROUTINES

=over 4

=item update_nameservers_config()

Updates name server settings in /etc/wwwacct.conf. This function takes up to
four optional arguments, nameserver, nameserver2, nameserver3, nameserver4,
and updates the NS, NS2, NS3, NS4 entries in wwwacct.conf, respectively.

This function has no returns.

=cut

our $wwwacct_ref;

sub update_nameservers_config {
    my ( $args, $metadata ) = @_;

    $wwwacct_ref ||= Cpanel::Config::LoadWwwAcctConf::loadwwwacctconf();
    my $lh = _locale();
    unless ($wwwacct_ref) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $lh->maketext('Unable to read current name server configuration.');
        return;
    }

    my %keys2args = (
        'NS'  => 'nameserver',
        'NS2' => 'nameserver2',
        'NS3' => 'nameserver3',
        'NS4' => 'nameserver4'
    );

    foreach my $key ( 'NS', 'NS2', 'NS3', 'NS4' ) {
        my $val = $args->{ $keys2args{$key} };
        next unless defined $val;
        unless ( $val eq '' || Cpanel::Validate::NameServer::is_valid($val) ) {
            $metadata->{'result'} = 0;
            $metadata->{'reason'} = $lh->maketext( '“[_1]” is not a valid name server.', $val );
            return;
        }
        $wwwacct_ref->{$key} = $val;
    }

    my $status = Cpanel::Config::SaveWwwAcctConf::savewwwacctconf($wwwacct_ref);
    unless ($status) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $lh->maketext('Unable to save name server configuration.');
        return;
    }

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return;
}

=item update_contact_email()

Updates email address for system administrator in /etc/wwwacct.conf. This
function takes a required argument, contact_email, and updates the
CONTACTEMAIL entry in wwwacct.conf.

This function has no returns.

=cut

sub update_contact_email {
    my ( $args, $metadata ) = @_;

    my $lh = _locale();

    my $email = Whostmgr::API::1::Utils::get_required_argument( $args, 'contact_email' );
    unless ( $email eq '' || Cpanel::Validate::EmailRFC::is_valid_remote($email) ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $lh->maketext( '“[_1]” is not a valid email address.', $email );
        return;
    }

    $wwwacct_ref ||= Cpanel::Config::LoadWwwAcctConf::loadwwwacctconf();
    unless ($wwwacct_ref) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $lh->maketext('Unable to read current email configuration.');
        return;
    }

    $wwwacct_ref->{'CONTACTEMAIL'} = $email;
    my $status = Cpanel::Config::SaveWwwAcctConf::savewwwacctconf($wwwacct_ref);
    unless ($status) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $lh->maketext('Unable to save email configuration.');
        return;
    }

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return;
}

my $locale;

sub _locale {
    return $locale if $locale;

    return $locale = Cpanel::Locale->get_handle();
}

=back

=cut

1;
