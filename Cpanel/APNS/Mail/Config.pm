package Cpanel::APNS::Mail::Config;

# cpanel - Cpanel/APNS/Mail/Config.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::APNS::Mail::Config - Configuration for APNS for mail.

=head1 SYNOPSIS

    use Cpanel::APNS::Mail::Config;

    my $cert = Cpanel::APNS::Mail::Config::CERT_FILE();
    my $key = Cpanel::APNS::Mail::Config::KEY_FILE();
    my $db_file = Cpanel::APNS::Mail::Config::DB_FILE();

=head1 DESCRIPTION

This module is the central place to locate assets required
for iOS push.

=cut

use strict;

=head2 CERT_FILE

The location of the apple push notifications certificate
in PEM format with the topic com.apple.mail...

=over

=item Input

None

=item Output

The path to the file on the file system.

=back

=cut

sub CERT_FILE { return '/var/cpanel/ssl/mail_apns/cert.pem'; }

=head2 KEY_FILE

The location of the key that matches the CERT_FILE

=over

=item Input

None

=item Output

The path to the file on the file system.

=back

=cut

sub KEY_FILE { return '/var/cpanel/ssl/mail_apns/key.pem'; }

=head2 DB_FILE

The location of sqlite3 database for storing iOS APNS mail
registrations.

=over

=item Input

None

=item Output

The path to the sqlite database file on the file system.

=back

=cut

sub DB_FILE { return '/var/cpanel/apnspush.sqlite3'; }

1;
