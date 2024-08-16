package Cpanel::Pkgacct::Components::Logs::Utils;

# cpanel - Cpanel/Pkgacct/Components/Logs/Utils.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Pkgacct::Components::Logs::Utils

=head1 SYNOPSIS

    my $lookup_hr = Cpanel::Pkgacct::Components::Logs::Utils::get_user_log_files_lookup($username);

=head1 DESCRIPTION

Individually-tested logic for user log file backups and restorations.

=cut

use Cpanel::Config::LoadCpUserFile ();

use constant _POSSIBLE_USER_MAIL_LOG_TRAILERS => (
    'popbytes_log',
    'imapbytes_log',
);

use constant _POSSIBLE_DOMAIN_WWW_LOG_TRAILERS => (
    'ssl_log',
    'error_log',
    'bytes_log',
);

use constant _POSSIBLE_DOMAIN_FTP_LOG_TRAILERS => (
    'ftp_log',
    'ftpbytes_log',
);

=head1 FUNCTIONS

=head2 $lookup_hr = get_user_log_files_lookup( $USERNAME )

Returns a lookup hash (values are all undef) of possible user log filenames
(e.g., C<$username-imapbytes_log>) for account backup and restoration.

=cut

sub get_user_log_files_lookup {
    my ($username) = @_;

    my $cpuser_ref = Cpanel::Config::LoadCpUserFile::loadcpuserfile($username);
    my @DNS        = (
        $cpuser_ref->{'DOMAIN'},
        @{ $cpuser_ref->{'DOMAINS'} },
    );

    # TODO: combine this logic with Whostmgr::Accounts::Remove:: _killacct
    # except for the .offset files
    my $domain;
    my %possible_log_files = map { $_ => undef } (
        ( map { ( "$username-$_", "$username-$_.bkup" ) } _POSSIBLE_USER_MAIL_LOG_TRAILERS ),
        (
            map {
                $domain = $_;
                (
                    ( "$domain", "www.$domain", "$domain.bkup", "www.$domain.bkup" ),
                    ( map { ( "$domain-$_", "www.$domain-$_", "$domain-$_.bkup", "www.$domain-$_.bkup" ) } _POSSIBLE_DOMAIN_WWW_LOG_TRAILERS ),
                    ( map { ( "$domain-$_", "ftp.$domain-$_", "$domain-$_.bkup", "ftp.$domain-$_.bkup" ) } _POSSIBLE_DOMAIN_FTP_LOG_TRAILERS )
                ),
            } @DNS
        )
    );

    return \%possible_log_files;
}

1;
