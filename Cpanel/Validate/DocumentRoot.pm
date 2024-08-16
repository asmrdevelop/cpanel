package Cpanel::Validate::DocumentRoot;

# cpanel - Cpanel/Validate/DocumentRoot.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Validate::DocumentRoot - Validation for document roots

=head1 DESCRIPTION

Historically, functions that created web virtual hosts responded to invalid
document roots by “coercing” them into valid values. This module facilitates
a workflow wherein such values are rejected instead.

=cut

#----------------------------------------------------------------------

use Cpanel::Imports;

use Cpanel::Exception        ();
use Cpanel::Linux::Constants ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 validate_subdomain_document_root_or_die( $PATH )

This validation rejects invalid data rather than coercing.
It forbids a leading slash and various characters that the subdomain creation
functions silently remove. It also requires a leading C<public_html/> if the
server’s C<publichtmlsubsonly> option is enabled.

It is recommended that new interfaces that use L<Cpanel::Sub>’s
C<addsubdomain()> or C<change_doc_root()> first validate input via this
function.

Nothing is returned.

=cut

sub validate_subdomain_document_root_or_die ($specimen) {

    # IMPORTANT: Maintain parity between this logic and that in
    # addsubdomain().

    validate_subdomain_document_root_characters_or_die($specimen);

    if ( 0 == rindex( $specimen, '/', 0 ) ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The document root must be a relative path. It must not begin with a slash (“[_1]”).', ['/'] );
    }

    require Cpanel::Validate::FilesystemPath;
    Cpanel::Validate::FilesystemPath::die_if_any_relative_nodes($specimen);

    require Cpanel::Config::LoadCpConf;
    my $cpconf = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();

    if ( $cpconf->{'publichtmlsubsonly'} ) {
        if ( 0 != rindex( $specimen, 'public_html/', 0 ) ) {
            die Cpanel::Exception::create( 'InvalidParameter', 'The document root must begin with “[_1]”.', ['public_html/'] );
        }
    }

    return;
}

=head2 validate_subdomain_document_root_characters_or_die( $PATH )

Like C<validate_subdomain_document_root_or_die()> but only rejects specific
character sequences and length. It doesn’t require, e.g., a relative path,
and it doesn’t enforce F<public_html/> relative to system configuration.

Nothing is returned.

=cut

sub validate_subdomain_document_root_characters_or_die ($specimen) {
    my $err;

    if ( !length $specimen || $specimen =~ m/[\\?%*:|"<>=]|\s/ ) {
        $err = locale()->maketext( 'Directory paths cannot be empty, contain whitespace, or contain the following characters: [join, ,_*]', qw(\ ? % * : | " < > =) );
    }
    elsif ( $specimen =~ m/\$\.*\{.*\}/s ) {    # '.' characters separating the '${' may be munged out later by Cpanel::SafeDir
        $err = locale()->maketext('Directory paths cannot contain interpolation sequences.');
    }
    elsif ( length($specimen) > Cpanel::Linux::Constants::PATH_MAX() ) {
        $err = locale()->maketext('Directory path length exceeds PATH_MAX.');
    }
    else {
        for my $bad (qw( .. // )) {
            if ( -1 != index( $specimen, $bad ) ) {
                $err = locale()->maketext( 'Directory paths cannot contain “[_1]”.', $bad );
            }
        }
    }

    if ($err) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid document root. ([_2])', [ $specimen, $err ] );
    }

    return;
}

1;
