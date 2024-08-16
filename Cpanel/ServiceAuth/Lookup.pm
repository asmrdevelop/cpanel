
# cpanel - Cpanel/ServiceAuth/Lookup.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::ServiceAuth::Lookup;

use strict;
use warnings;

use Cpanel::ConfigFiles      ();
use Cpanel::StringFunc::Case ();
use Cpanel::PwCache          ();

=encoding utf-8

=head1 NAME

Cpanel::ServiceAuth::Lookup - Lookup the current service auth user

=head1 SYNOPSIS

    use Cpanel::ServiceAuth::Lookup;

    my $auth_data = Cpanel::ServiceAuth::Lookup::lookup_service_auth_user($service);

    print $auth_data->{'USERNAME'};

    print $auth_data->{'PASSWD'};

=cut

=head2 lookup_service_auth_user

Summary...

=over 2

=item Input

=over 3

=item C<SCALAR>

    The service to lookup the pseudo user for.
    Examples: exim|smtp|imap|pop

=back

=item Output

=over 3

=item C<HASHREF>

    A hashref that is consumable by Cpanel::MailAuth::*

=back

=back

=cut

sub lookup_service_auth_user {
    my ($service) = @_;

    my ( $sendfile, $recvfile ) = map { "$Cpanel::ConfigFiles::SERVICEAUTH_DIR/$service/$_" } qw( send recv );

    open( my $service_auth_fh2, '<', $recvfile ) or do {
        _log_failure("Failed to open $recvfile: $!");
        return undef;
    };
    my $service_auth_pass = readline($service_auth_fh2);
    close($service_auth_fh2);

    open( my $service_auth_fh, '<', $sendfile ) or do {
        _log_failure("Failed to open $sendfile: $!");
        return undef;
    };
    my $service_auth_user = readline($service_auth_fh);
    close($service_auth_fh);

    my ( $uid, $gid ) = ( Cpanel::PwCache::getpwnam('cpanel') )[ 2, 3 ];    #must be a valid account
    if ( !$uid || !$gid ) {
        _log_failure("Failed to getpwnam for user “cpanel”!");
        return undef;
    }

    return {
        'USERNAME'     => Cpanel::StringFunc::Case::ToLower($service_auth_user),
        'ADDRESS'      => 'cpanel@localhost',
        'PASSWD'       => $service_auth_pass,
        'UID'          => $uid,
        'GID'          => $gid,
        'HOME'         => '/usr/local/cpanel/var/serviceauth',
        'MAILDIR'      => '/usr/local/cpanel/var/serviceauth',
        'FORMAT'       => 'maildir',
        'ACCOUNT_TYPE' => 'serviceauth',
    };
}

sub _log_failure {
    return print STDERR __PACKAGE__ . ': ' . $_[0] . "\n";    #dovecot will write this to syslog

}

1;
