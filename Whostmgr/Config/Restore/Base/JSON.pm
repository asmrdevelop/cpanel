package Whostmgr::Config::Restore::Base::JSON;

# cpanel - Whostmgr/Config/Restore/Base/JSON.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Config::Restore::Base::JSON

=head1 DESCRIPTION

This is an intermediate class that subclasses
L<Whostmgr::Config::Restore::Base>. It provides “plumbing” for reading
a configuration from a JSON file in a backup.

This class’s counterpart is
L<Whostmgr::Config::Backup::Base::JSON>.

=head1 REQUIRED METHODS

This class provides a C<_restore()> implementation; subclasses must
implement any other methods that L<Whostmgr::Config::Restore::Base>
requires.

Additionally, subclasses of this class must provide:

=over

=item * C<_restore_from_structure($STRUCT)> - Restore whatever is in
$STRUCT—which should be the same structure as what the
corresponding L<Whostmgr::Config::Backup::Base::JSON> subclass’s
C<_get_backup_structure()> method returns.

=back

=cut

#----------------------------------------------------------------------

use parent qw( Whostmgr::Config::Restore::Base );

use Cpanel::JSON::XS ();    # NB: This is a CPAN module.

use Cpanel::LoadFile ();

#----------------------------------------------------------------------

sub _restore ( $self, $parent ) {

    my $module_name_lc = ref($self) =~ s<.+::><>r =~ tr<A-Z><a-z>r;

    my $backup_path = $parent->{'backup_path'};

    my $gl_path = "$backup_path/cpanel/system/$module_name_lc/$module_name_lc.json";

    if ( my $json = Cpanel::LoadFile::load_if_exists($gl_path) ) {

        # Cpanel::JSON mangles the UTF-8 such that the SQLite in the
        # WHM API v1 call screws it up on insert. Cpanel::JSON::XS appears
        # to work, so let’s use that.
        my $struct = Cpanel::JSON::XS::decode_json($json);
        $self->_restore_from_structure($struct);
    }

    return ( 1, ( ref $self ) . ': ok' );
}

1;
