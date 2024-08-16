package Cpanel::SSL::Auto::Exclude::Get;

# cpanel - Cpanel/SSL/Auto/Exclude/Get.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Context                       ();
use Cpanel::Exception                     ();
use Cpanel::Transaction::File::JSONReader ();
use Cpanel::Debug                         ();

our $EXCLUDES_DIR = '/var/cpanel/ssl/autossl/excludes';

=encoding utf-8

=head1 NAME

Cpanel::SSL::Auto::Exclude::Get - Gets the AutoSSL domain excludes list for a user.

=head1 SYNOPSIS

    use Cpanel::SSL::Auto::Exclude::Get ();

    my @excludes = Cpanel::SSL::Auto::Excludes::Get::get_user_excluded_domains($user);

=head1 DESCRIPTION

This module performs the get/read options for the AutoSSL domain excludes lists. The AutoSSL domain excludes lists are there to
disable autossl for specific domains for a user.

=cut

=head2 get_user_excludes_file_path

This function assembles the full path to the excludes file for a specific user.

=head3 Input

=over 3

=item C<SCALAR> user

    The name of the user to get the AutoSSL domain excludes file path for.

=back

=head3 Output

=over 3

=item C<SCALAR> path

    The AutoSSL domain excludes file path for a user.

=back

=head3 Exceptions

=over 3

=item Cpanel::Exception::MissingParameter

    Thrown if the user parameter is not supplied.

=item Anything Cpanel::Transaction::File::JSONReader can throw

    This module uses the above module to open and read the excludes file. Please see that module for more exceptions that may be thrown.

=back

=cut

sub get_user_excludes_file_path {
    my ($user) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'user' ] ) if !$user;

    return "$EXCLUDES_DIR/$user.json";
}

=head2 get_user_excluded_domains

This function gets the list of AutoSSL excluded domains for a user.

=head3 Input

=over 3

=item C<SCALAR> user

    The name of the user to get the AutoSSL excluded domains list for.

=back

=head3 Output

=over 3

=item C<ARRAY>

    An array of domains that have been excluded from AutoSSL for the supplied user.

=back

=head3 Exceptions

=over 3

=item Cpanel::Exception::MissingParameter

    Thrown if the user parameter is not supplied.

=item Anything Cpanel::Transaction::File::JSONReader can throw

    This module uses the above module to open and read the excludes file. Please see that module for more exceptions that may be thrown.

=back

=cut

sub get_user_excluded_domains {
    my ($user) = @_;

    Cpanel::Context::must_be_list();

    my $path = get_user_excludes_file_path($user);
    return if !-e $path;

    my $reader = Cpanel::Transaction::File::JSONReader->new( path => $path );
    my $data   = $reader->get_data();

    return if !$data;    # nothing excluded yet

    if ( 'HASH' ne ref $data || !keys %$data || !defined $data->{excluded_domains} ) {
        Cpanel::Debug::log_warn("Invalid data detected in: $path");

        return;
    }

    return @{ $data->{excluded_domains} };
}

1;
