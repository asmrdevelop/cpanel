
# cpanel - Cpanel/ImagePrep/Check/api_token.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::ImagePrep::Check::api_token;

use cPstrict;
use parent 'Cpanel::ImagePrep::Check';
use POSIX ();

use Cpanel::Security::Authn::APITokens::whostmgr ();

=head1 NAME

Cpanel::ImagePrep::Check::api_token - A subclass of C<Cpanel::ImagePrep::Check>.

=cut

sub _description {
    return <<EOF;
Check whether any WHM API tokens exist.
EOF
}

sub _check ($self) {

    # Only check for WHM API tokens because any cPanel API tokens would require the existence of a cPanel user, which we disallow for template VMs.
    my $apitokens = Cpanel::Security::Authn::APITokens::whostmgr->new( { user => 'root' } );
    my @tokens    = sort { $a->get_name cmp $b->get_name } values %{ $apitokens->read_tokens };
    if (@tokens) {
        die <<EOF;
You have one or more API tokens configured. This is not a supported configuration for template VMs.

API token(s):
@{[join "\n", map { sprintf("  - %s (created %s)", $_->get_name, POSIX::strftime('%Y-%m-%d %H:%M:%S %z', localtime($_->get_create_time) ) ) } @tokens]}
EOF
    }
    $self->loginfo('No API tokens');
    return;
}

1;
