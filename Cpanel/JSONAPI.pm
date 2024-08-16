
# cpanel - Cpanel/JSONAPI.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::JSONAPI;

use strict;
use warnings;

use Cpanel::JSON    ();
use Cpanel::Autodie ();

=head1 NAME

Cpanel::JSONAPI

=head1 DESCRIPTION

Common utility functions for handling JSON-based API input.

Currently this is used for:

=over

=item * WHM API 1

=item * UAPI (cPanel)

=back

=head1 ENVIRONMENT

An assumption of this module is that it is being called from an environment where HTTP request
environment variables are set. If you use it either in cpsrvd or in a child spawned by cpsrvd,
this assumption should be satisfied.

=head1 FUNCTIONS

=head2 parsejson(FH)

=head3 Description

Read the request's POST body, and decode the JSON in the request.

This function may be thought of as being analogous to C<Cpanel::Form::parseform()>, but for
JSON requests instead of x-www-form-urlencoded requests.

=head3 Arguments

=over

=item FH - Optional file handle reference. If not provided it will use STDIN.

=back

=head3 Returns

This function returns a hashref containing the decoded data structure from the request's POST body.
Any keys beginning with the special "file-" prefix Cpanel::Form uses for file uploads will be
removed from the hashref.

=head3 Throws

An exception will be thrown if any of the following problems occur:

=over

=item * $ENV{CONTENT_TYPE} is not set to 'application/json'.

=item * The request body cannot be decoded as JSON.

=item * A timeout occurs while reading or decoding the request. (For example, if the client sends an
incorrect Content-Length header, and the read blocks.)

=item * The JSON deserialized into any datatype other than a hashref.

=back

=cut

sub parsejson {
    my $fh = shift || \*STDIN;
    if ( !is_json_request() ) {
        die "parsejson(): Expected Content-Type 'application/json', but got '" . ( $ENV{CONTENT_TYPE} || '' ) . "'.\n";    # Developer error
    }

    my $json    = _read($fh) || '{}';
    my $formref = Cpanel::JSON::Load($json);
    if ( 'HASH' ne ref $formref ) {
        die "parsejson(): Invalid JSON data.\n";
    }
    delete %$formref{ grep { !rindex( $_, 'file-', 0 ) } keys %$formref };
    return $formref;
}

=head2 has_nested_structures(ARGS)

=head3 Description

Check whether a hash ref (presumably originating from a JSON request) contains any nested
data structures. This is so that UAPI and WHM API 1 may reject requests containing these
structures except in the specific cases where they're expected.

For example:

  With { a => "b" } the answer would be no

  But with { a => ["b"] } the answer would be yes

Note: This is for a pre-validation stage and is not meant to replace the validation that must be
done inside of individual implementations.

=head3 Arguments

=over

=item * ARGS - Hash ref - (Required) Provide the same hash ref that you got back from parsejson().

=back

=head3 Returns

 Boolean:
   - 1 if there is at least one reference underneath
   - 0 if no references exist underneath

=head3 Throws

An exception will be thrown if the provided argument structure is not a hash ref.

=cut

sub has_nested_structures {
    my ($args) = @_;
    ref($args) eq 'HASH' or die 'Argument structure must be a hash ref';    # Developer error - do not translate
    for my $k ( sort keys %$args ) {
        if ( ref $args->{$k} ) {
            return 1;
        }
    }
    return 0;
}

=head2 is_json_request()

=head3 Description

Check whether the current request is using JSON input.

Assumption: This is being run under cpsrvd, where the CONTENT_TYPE environment variable will be set.

=head3 Arguments

None

=head3 Returns

  Boolean:
    - 1 if the request is using JSON input
    - 0 if the request is not using JSON input

=cut

sub is_json_request {
    return ( ( $ENV{CONTENT_TYPE} || '' ) eq 'application/json' );
}

sub _read {
    my $fh = shift;
    my $json;
    my $bytes_to_read = $ENV{CONTENT_LENGTH} || 0;
    my $bytes_read    = 0;
    while ( $bytes_to_read > 0 and $bytes_read = Cpanel::Autodie::read( $fh, my $buffer, $bytes_to_read ) ) {
        $bytes_to_read -= $bytes_read;
        $json .= $buffer;
    }
    return $json;
}

1;
