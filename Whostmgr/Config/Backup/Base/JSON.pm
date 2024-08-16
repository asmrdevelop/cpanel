package Whostmgr::Config::Backup::Base::JSON;

# cpanel - Whostmgr/Config/Backup/Base/JSON.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Config::Backup::Base::JSON

=head1 DESCRIPTION

This is an intermediate class that subclasses
L<Whostmgr::Config::Restore::Base>. It provides “plumbing” for saving
a configuration from a JSON file in a backup.

This class’s counterpart is
L<Whostmgr::Config::Restore::Base::JSON>.

=head1 REQUIRED METHODS

This class provides a C<_backup()> implementation; subclasses must
implement any other methods that L<Whostmgr::Config::Backup::Base>
requires.

Additionally, subclasses of this class must provide:

=over

=item * C<_get_backup_structure()> - Returns a JSON-stringifiable
data structure that will be saved in the backup.

=back

=cut

#----------------------------------------------------------------------

use parent qw( Whostmgr::Config::Backup::Base );

use Cpanel::JSON     ();
use Cpanel::TempFile ();

#----------------------------------------------------------------------

=head1 METHODS

=head2 I<OBJ>->_save_json( $PARENT, $STRUCT )

Sometimes it’s useful to back up a JSON data structure in I<addition>
to individual files. For such cases, you can define your own C<_backup()>
implementation that overrides the one that this class provides; in that
implementation you can call then call this method.

=cut

sub _save_json ( $self, $parent, $struct ) {

    # We don’t delete the TempFile object directly
    # because there should be no need. We do need to attach it
    # to $self so that it lasts long enough for the backup to be
    # assembled.
    $self->{'temp_obj'} = Cpanel::TempFile->new();

    my $temp_dir = $self->{'temp_obj'}->dir();

    my $module_name_lc  = ( ( ref $self ) =~ s<.+::><>r );
    my $module_name2_lc = ( ( ref $self ) =~ s<.+::(.+::.+)><$1>r );

    tr<A-Z><a-z> for ( $module_name_lc, $module_name2_lc );

    Cpanel::JSON::DumpFile( "$temp_dir/$module_name_lc.json", $struct );

    my $files_to_copy = $parent->{'files_to_copy'}{"cpanel::$module_name2_lc"} = {};

    my $reldir = $module_name2_lc =~ s<::></>r;

    $files_to_copy->{"$temp_dir/$module_name_lc.json"} = { dir => "cpanel/$reldir" };

    return;
}

sub _backup ( $self, $parent ) {    ## no critic qw(Prototype)
    $self->_save_json( $parent, $self->_get_backup_structure() );

    return ( 1, ( ref $self ) . ': ok' );
}

1;
