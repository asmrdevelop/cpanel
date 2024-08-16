
# cpanel - Cpanel/Validate/Html.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Validate::Html;

use strict;
use warnings;

use Cpanel::Exception ();

=head1 MODULE

C<Cpanel::Validate::Html>

=head1 NAME

C<Cpanel::Validate::Html> - Utilities for validating HTML

=head1 SYNOPSIS

    use Cpanel::Validate::HTML;
    Cpanel::Validate::HTML::no_common_html_entities_or_die('&amp;|&lt;|&gt;|&quot;|&#39', 'name');
    Cpanel::Validate::HTML::no_special_characters_or_die('&Ihave<specialChars\'">', 'name');

=head1 DESCRIPTION

C<Cpanel::Validate::Html> provides validators to prevent html entities and special characters in strings.

=head1 FUNCTIONS

=head2 no_common_html_entities_or_die(SPECIMEN, NAME)

Checks if there are HTML entities in the SPECIMEN. If there are dies.

=head3 ARGUMENTS

=over

=item SPECIMEN - string

String being tested.

=item NAME - string

Optional. Field name to report in exception.

=back

=head3 THROWS

=over

=item When any of C<&amp;>, C<&gt;>, C<&lt;>, C<&quot;>, or C<&#39;> exists in the specimen

=back

=cut

sub no_common_html_entities_or_die {
    my ( $value, $name ) = @_;
    if ( $value =~ m/&amp;|&lt;|&gt;|&quot;|&#39;/ ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The argument cannot contain special characters: [list_or,_1].',        [ [qw(& < > " ')] ] ) if !defined $name || $name eq '';
        die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” argument cannot contain special characters: [list_or,_2].', [ $name, [qw(& < > " ')] ] );
    }
    return;
}

=head2 no_special_characters_or_die(SPECIMEN, NAME)

Checks if there are HTML entities in the SPECIMEN. If there are dies.

=head3 ARGUMENTS

=over

=item SPECIMEN - string

String being tested.

=item NAME - string

Optional. Field name to report in exception.

=back

=head3 THROWS

=over

=item When any of &, <, >, ", or ' exists in the specimen.

=back

=cut

sub no_special_characters_or_die {
    my ( $value, $name ) = @_;
    if ( $value =~ m/[&<>"']/ ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The argument cannot contain special characters: [list_or,_1].',        [ [qw(& < > " ')] ] ) if !defined $name || $name eq '';
        die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” argument cannot contain special characters: [list_or,_2].', [ $name, [qw(& < > " ')] ] );
    }
    return;
}

1;
