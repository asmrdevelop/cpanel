package Cpanel::PHPFPM::Config;

# cpanel - Cpanel/PHPFPM/Config.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::PHPFPM::Constants ();

our $touch_file_default_accounts_to_fpm = $Cpanel::PHPFPM::Constants::system_yaml_dir . '/' . $Cpanel::PHPFPM::Constants::touch_file;

=encoding utf-8

=head1 NAME

Cpanel::PHPFPM::Config - Low cost functions to set or get config values.

=head1 SYNOPSIS

    use Cpanel::PHPFPM::Config;

    my $ret = Cpanel::PHPFPM::Config::get_default_accounts_to_fpm ();
    Cpanel::PHPFPM::Config::set_default_accounts_to_fpm ('ea-php99');

=head1 DESCRIPTION

Miscellaneous functions to support API calls for config options.

=head2 set_default_accounts_to_fpm

Creates flag file to indicate to rest of system that it should use PHP-FPM as the default PHP handler when creating new accounts

=over 2

=item Input

=back

=over 3

=item C<SCALAR>

    True or false value to indicate whether to create or remove the touchfile, respectively.

=back

=over 2

=item Output

=back

=over 3

=item C<SCALAR>

    Returns 1

=back

=cut

sub set_default_accounts_to_fpm {
    my ($default) = @_;

    my $file_exists = get_default_accounts_to_fpm();
    if ( $default && !$file_exists ) {
        require File::Path;
        File::Path::make_path($Cpanel::PHPFPM::Constants::system_yaml_dir);
        open my $fh, '>', $touch_file_default_accounts_to_fpm or do {
            require Cpanel::Exception;
            die Cpanel::Exception::create(
                'IO::FileCreateError',
                [
                    path  => $touch_file_default_accounts_to_fpm,
                    error => $!,
                ]
            );
        };
    }
    elsif ( !$default && $file_exists ) {
        unlink $touch_file_default_accounts_to_fpm;
    }

    return 1;
}

=head2 get_default_accounts_to_fpm

Determines if PHP-FPM is set as the default PHP handler

=over 2

=item Output

=back

=over 3

=item C<SCALAR>

    Returns 1 if true, 0 if false

=back

=cut

sub get_default_accounts_to_fpm {
    return ( -f $touch_file_default_accounts_to_fpm ) ? 1 : 0;
}

=head2 should_default

Determines if PHP-FPM should be set as the default PHP handler.

=over 2

=item Output

=back

=over 3

=item C<SCALAR>

    Returns 1 if true, 0 if false

=back

=cut

sub should_default {
    require Cpanel::Sys::Hardware::Memory;
    my $total_sys_mem = Cpanel::Sys::Hardware::Memory::get_installed();
    if ( $total_sys_mem < 2048 ) {
        return 0;
    }
    else {
        return 1;
    }
}

1;
