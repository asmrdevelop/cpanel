package Cpanel::SSL::DefaultKey::Constants;

# cpanel - Cpanel/SSL/DefaultKey/Constants.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::SSL::DefaultKey::Constants

=head1 SYNOPSIS

    my @possible = Cpanel::SSL::DefaultKey::Constants::OPTIONS;

=head1 DESCRIPTION

Storage of constants for the SSL/TLS default-key settings.

=cut

#----------------------------------------------------------------------

use Cpanel::SSL::KeyTypeLabel ();

#----------------------------------------------------------------------

=head1 CONSTANTS

=head2 OPTIONS

A list of options, in the order in which they should appear in UIs.

=cut

use constant OPTIONS => (
    'rsa-2048',
    'ecdsa-secp384r1',
    'ecdsa-prime256v1',
    'rsa-4096',
);

=head2 OPTIONS_AND_LABELS

A key/value list of options and labels. The order
matches C<OPTIONS>.

(In actuality this is a function, not a constant.)

=cut

sub OPTIONS_AND_LABELS() {
    local ( $@, $! );
    require Cpanel::Locale;

    my $lh = Cpanel::Locale->get_handle();

    return map { ( $_ => Cpanel::SSL::KeyTypeLabel::to_label($_) ) } OPTIONS;
}

=head2 KEY_DESCRIPTIONS

A key/value list of options and descriptions. The order
matches C<OPTIONS>.

(In actuality this is a function, not a constant.)

=cut

sub KEY_DESCRIPTIONS() {
    require Cpanel::Locale;

    my $lh = Cpanel::Locale->get_handle();

    return {
        "rsa-2048"         => $lh->maketext("[asis,RSA] is more compatible with older clients (for example, browsers older than [asis,Internet Explorer] 11) than [asis,ECDSA]. New installations of [asis,cPanel amp() WHM] ship with this setting."),
        "rsa-4096"         => $lh->maketext( "[asis,RSA] is more compatible with older clients (for example, browsers older than [asis,Internet Explorer] 11) than [asis,ECDSA]. This is more secure than [_1]-bit, but will perform slower than [_1]-bit keys.", 'RSA, 2,048' ),
        "ecdsa-prime256v1" => $lh->maketext("[asis,ECDSA] allows websites to support [asis,Internet Explorer] 11 and retain compliance with [output,acronym,PCI,Payment Card Industry] standards."),
        "ecdsa-secp384r1"  => $lh->maketext("[asis,ECDSA] allows websites to support [asis,Internet Explorer] 11 and retain compliance with [output,acronym,PCI,Payment Card Industry] standards. [asis,secp384r1] is more secure than [asis,prime256v1], but may perform slower."),
    };
}

use constant USER_SYSTEM => 'system';

1;
