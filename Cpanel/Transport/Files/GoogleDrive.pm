
# cpanel - Cpanel/Transport/Files/GoogleDrive.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Transport::Files::GoogleDrive;

use strict;
use warnings;
use File::Spec                                            ();
use Cpanel::Transport::Response                           ();
use File::Basename                                        ();
use File::Temp                                            ();
use Cpanel::Locale                                        ();
use Cpanel::FileUtils::Write                              ();
use Cpanel::Transport::Files                              ();
use Cpanel::Transport::Files::GoogleDrive::CredentialFile ();

use constant {
    'GOOGLE_FOLDER_MIMETYPE' => 'application/vnd.google-apps.folder',
};

our @ISA = ('Cpanel::Transport::Files');
my $locale;

=head1 NAME

Cpanel::Transport::Files::GoogleDrive

=head1 SYNOPSIS

This module is exclusively invoked via its superclass Cpanel::Transport::Files
within the backup transport code.

=head1 DESCRIPTION

This module implements the transport used to upload backups to Google Drive.

=head1 SUBROUTINES

=head2 new

Instantiate a new instance

=cut

sub new {
    my ( $class, $OPTS, $CFG ) = @_;
    $locale ||= Cpanel::Locale->get_handle();

    Cpanel::Transport::Files::load_module('Net::Google::Drive::Simple');

    $OPTS->{'gd'} = _server_login($OPTS);

    my $self = bless $OPTS, $class;
    $self->{'config'} = $CFG;

    return $self;
}

=head2 _missing_parameters

Generate a list of missing parameters from proposed set of parameters for creating an instance

=cut

sub _missing_parameters {
    my ($param_hashref) = @_;

    my @result = ();
    foreach my $key (qw/client_id client_secret/) {
        if ( !defined $param_hashref->{$key} ) {
            push @result, $key;
        }
    }

    my %defaults = (
        'folder'  => '',
        'timeout' => '30',
    );
    foreach my $key ( keys %defaults ) {
        if ( !defined $param_hashref->{$key} ) {
            $param_hashref->{$key} = $defaults{$key};
        }
    }

    return @result;
}

=head2 _get_valid_parameters

Return a list of special, valid parameters for creating an instance

=cut

sub _get_valid_parameters {
    return qw/client_id client_secret folder timeout/;
}

=head2 get_path

Return a path under which files will be uploaded/downloaded

=cut

sub get_path {
    my ($self) = @_;

    return "/$self->{'folder'}";
}

=head2 _validate_parameters

Ensure that the values for the expected parameters are valid

=cut

sub _validate_parameters {
    my ($param_hashref) = @_;
    my @result = ();

    foreach my $key (qw/client_id client_secret/) {
        if ( !defined $param_hashref->{$key} ) {
            push @result, $key;
        }
    }

    # Remove leading/trailing slashes from folder
    $param_hashref->{'folder'} =~ s|^/+||;
    $param_hashref->{'folder'} =~ s|/+$||;

    push @result, 'timeout' unless Cpanel::Transport::Files::value_is_in_range( value => $param_hashref->{'timeout'}, min => 1, max => 900 );

    return @result;
}

=head2 _server_login

Ensure there are no missing parameters, all parameters are valid, and
create an instance of the object which talks directly with Google Drive

=cut

sub _server_login {    ## no critic(RequireArgUnpacking) - wrongly getting the perlcritic "unpack" error
    my ($OPTS) = @_;

    my @missing = _missing_parameters($OPTS);
    if (@missing) {
        die Cpanel::Transport::Exception::MissingParameter->new(
            \@_, 0,
            $locale->maketext( '“[_1]” is missing the following parameters: [list_and,_2]', __PACKAGE__, \@missing ),
            \@missing
        );
    }

    my @invalid = _validate_parameters($OPTS);
    if (@invalid) {
        die Cpanel::Transport::Exception::InvalidParameter->new(
            \@_, 0,
            $locale->maketext( '“[_1]” the following parameters were invalid: [list_and,_2]', __PACKAGE__, \@invalid ),
            \@invalid
        );
    }

    my $credentials_file = Cpanel::Transport::Files::GoogleDrive::CredentialFile::credential_file_from_id( $OPTS->{'client_id'} );
    my $gd               = Net::Google::Drive::Simple->new( 'custom_file' => $credentials_file, 'version' => 3 );

    return $gd;
}

=head2 _post_deletion_cleanup

Delete the credentials file, triggered by deleting the transport.

=cut

# Note that this $self is just the module name, not like the others
sub _post_deletion_cleanup {
    my ( $self, $info ) = @_;

    if ( defined( $info->{'client_id'} ) ) {
        my $credentials_file = Cpanel::Transport::Files::GoogleDrive::CredentialFile::credential_file_from_id( $info->{'client_id'} );
        unlink $credentials_file;
    }
    return;
}

=head2 _error_msg

Return any errors generated during the last Google Drive operation

=cut

sub _error_msg {
    my ($self) = @_;

    return ( $self->{'gd'}->error() || '' );
}

=head2 _put

Upload a file to Google Drive

=cut

sub _put {    ## no critic(RequireArgUnpacking) - wrongly getting the perlcritic "unpack" error
    my ( $self, $local, $remote ) = @_;

    my $gd = $self->{'gd'};

    # Figure out the remote path
    my ( $volume, $directory, $remote_file_name ) = File::Spec->splitpath($remote);

    if ( length $directory > 1 ) {
        $directory =~ s{/$}{}xms;
    }

    my $children = $gd->children($directory);

    if ( !$children ) {
        die Cpanel::Transport::Exception->new( \@_, 0, "Error finding directory '$directory' on drive" );
    }

    my $dir_id = $self->_get_path_id($directory);

    # Find any files in the directory with the same name as the file we are uploading
    # and save their ID's for deletion.  Google Drive allows multiple files in the directory
    # to have the same name & we don't want multiple files of the same name piling up in
    # a date folder if we trigger backups multiple times in a day.
    my @file_ids_for_deletion;

    for my $child (@$children) {
        next if $child->kind() ne 'drive#file';
        next if $child->is_folder();
        next if $child->name() ne $remote_file_name;

        push @file_ids_for_deletion, $child->id();
    }

    my $file_data;
    if ( -e $local && -z _ ) {

        # Google doesn't like zero sized files, upload a single byte instead
        my $fh = File::Temp->new();
        print $fh "\x00";
        close $fh;

        $file_data = $gd->upload_file(
            $fh->filename(),
            {
                'parents' => [$dir_id],
                'name'    => $remote_file_name,
            },
        );
    }
    else {
        $file_data = $gd->upload_file(
            $local,
            {
                'parents' => [$dir_id],
                'name'    => $remote_file_name,
            },
        );
    }

    if ( !$file_data ) {
        die Cpanel::Transport::Exception->new( \@_, 0, "Error uploading $local:  " . $self->_error_msg() );
    }

    # Only delete the files of the same name if the upload has succeeded
    foreach my $id (@file_ids_for_deletion) {
        if ( !$gd->delete_file($id) ) {
            print STDERR "Error deleting $remote:  " . $self->_error_msg();
        }
    }

    return Cpanel::Transport::Response->new( \@_, 1, 'OK' );
}

=head2 _get

Download a file from Google Drive

=cut

sub _get {    ## no critic(RequireArgUnpacking) - wrongly getting the perlcritic "unpack" error
    my ( $self, $remote, $local ) = @_;

    my $gd = $self->{'gd'};

    # Figure out the remote path
    my ( $volume, $directory, $remote_file_name ) = File::Spec->splitpath($remote);

    if ( length $directory > 1 ) {
        $directory =~ s{/$}{}xms;
    }

    my $children = $gd->children($directory);

    if ( !$children ) {
        die Cpanel::Transport::Exception->new( \@_, 0, "Error finding directory '$directory' on drive" );
    }

    if ( !@{$children} ) {
        die Cpanel::Transport::Exception->new( \@_, 0, "Error finding path '$remote': directory '$directory' is empty" );
    }

    my $id_to_download = $self->_get_path_id($remote);
    my $content        = $gd->get_file( $id_to_download, { 'alt' => 'media' } );

    if ( defined $content ) {
        Cpanel::FileUtils::Write::write( $local, $content );
        return Cpanel::Transport::Response->new( \@_, 1, 'OK' );
    }

    die Cpanel::Transport::Exception->new( \@_, 0, "Error downloading $remote:  " . $self->_error_msg() );
}

=head2 _ls

List the contents of a Google Drive folder

=cut

sub _ls {    ## no critic(RequireArgUnpacking) - wrongly getting the perlcritic "unpack" error
    my ( $self, $path ) = @_;

    my $gd = $self->{'gd'};

    chomp $path;
    if ( length $path > 1 ) {
        $path =~ s{/$}{}xms;
    }

    my $children = $gd->children($path);
    if ( !$children ) {
        die Cpanel::Transport::Exception->new( \@_, 0, "Path does not exist: '$path':  " . $self->_error_msg() );
    }

    my @ls;
    for my $child ( @{$children} ) {
        next if $child->kind() ne 'drive#file';
        my $name = $child->name();
        my $type = ( $child->mimeType() eq GOOGLE_FOLDER_MIMETYPE() ) ? "d" : "-";
        push @ls, "${type}rw-r--r-- X X X 0 X X X $name";
    }

    my @response = map { $self->_parse_ls_response($_) } @ls;
    return Cpanel::Transport::Response::ls->new( \@_, 1, 'Ok', \@response );
}

=head2 _mkdir

Create a Google Drive folder

=cut

sub _mkdir {    ## no critic(RequireArgUnpacking) - wrongly getting the perlcritic "unpack" error
    my ( $self, $path ) = @_;

    my $gd = $self->{'gd'};

    $path =~ s|/$||;
    $path =~ s|^/||;

    # Our algorithm is:
    # We walk each item and get its children
    # We look for the next item in the children
    # If it's empty or doesn't have the child, we create the child and set the new parent id
    # (The item itself always exists because we take care of it in the previous iteration)

    # First segment ('/') is definitely available, just return OK
    my @segments = File::Spec->splitdir($path)
      or return Cpanel::Transport::Response->new( \@_, 1, 'OK' );

    my $parent_id;
    my $path_to_create = '';
    unshift @segments, '/';

    # Each iteration takes care of the next node
    # So we ignore the last iteration
  SEGMENT:
    foreach my $idx ( 0 .. $#segments - 1 ) {
        my $segment = $segments[$idx]
          or next;

        my $next_segment_name = $segments[ $idx + 1 ];

        # We want to avoid double forward slash in the first two cases: / /foo
        if ( !$path_to_create ) {
            $path_to_create = '/';
        }
        elsif ( $path_to_create eq '/' ) {
            $path_to_create = "/$segment";
        }
        else {
            # We already have a segment set up
            $path_to_create .= "/$segment";
        }

        # Set the first parent_id
        $parent_id //= 'root';

        my $children = $gd->children($path_to_create);
        foreach my $child ( @{ $children || [] } ) {
            $child->mimeType() eq GOOGLE_FOLDER_MIMETYPE()
              or next;

            $child->name() eq $next_segment_name
              or next;

            # It exists, let's set its ID as the new part and move to the next segment
            $parent_id = $child->id();
            next SEGMENT;
        }

        # We couldn't find the next segment, create it, then move on to it
        my $folder_data = $gd->create_folder( $next_segment_name, $parent_id ) // {};
        if ( !$folder_data || !$folder_data->{'id'} ) {
            die Cpanel::Transport::Exception->new( \@_, 0, "Error mkdir on $path:  " . $self->_error_msg() );
        }

        $parent_id = $folder_data->{'id'};
    }

    return Cpanel::Transport::Response->new( \@_, 1, 'OK' );
}

sub _chdir {
    my ($self) = @_;

    # This has no real meaning for this
    return Cpanel::Transport::Response->new( \@_, 1, 'OK' );
}

=head2 _rmdir

Delete a Google Drive folder and all its contents

=cut

sub _rmdir {    ## no critic(RequireArgUnpacking) - wrongly getting the perlcritic "unpack" error
    my ( $self, $path ) = @_;

    my $gd = $self->{'gd'};

    if ( length $path > 1 ) {
        $path =~ s{/$}{}xms;
    }

    if ( $path eq '/' ) {
        die Cpanel::Transport::Exception->new( \@_, 0, 'Cannot delete top-level directory: /' );
    }

    my $id_to_delete = $self->_get_path_id(
        $path,
        sub { $_[0]->mimeType() eq GOOGLE_FOLDER_MIMETYPE() },
    );

    if ( !$gd->delete_file($id_to_delete) ) {
        die Cpanel::Transport::Exception->new( \@_, 0, "Error deleting $path:  " . $self->_error_msg() );
    }

    return Cpanel::Transport::Response->new( \@_, 1, 'OK' );
}

=head2 _delete

Delete a Google Drive file

=cut

sub _delete {    ## no critic(RequireArgUnpacking) - wrongly getting the perlcritic "unpack" error
    my ( $self, $path ) = @_;

    my $gd = $self->{'gd'};

    if ( length $path > 1 ) {
        $path =~ s{/$}{}xms;
    }

    if ( $path eq '/' ) {
        die Cpanel::Transport::Exception->new( \@_, 0, 'Cannot delete top-level directory: /' );
    }

    my $id_to_delete = $self->_get_path_id(
        $path,
        sub { $_[0]->mimeType() ne GOOGLE_FOLDER_MIMETYPE() },
    );

    if ( !$gd->delete_file($id_to_delete) ) {
        die Cpanel::Transport::Exception->new( \@_, 0, "Error deleting $path:  " . $self->_error_msg() );
    }

    return Cpanel::Transport::Response->new( \@_, 1, 'OK' );
}

sub _pwd {
    my ($self) = @_;

    # This has no real meaning for this
    return Cpanel::Transport::Response->new( \@_, 1, 'OK', '/' );
}

sub _get_path_id {    ## no critic(RequireArgUnpacking) - wrongly getting the perlcritic "unpack" error
    my ( $self, $path, $cb ) = @_;

    if ( length $path > 1 ) {
        $path =~ s{/$}{}xms;
    }

    # Main path is 'root'
    if ( $path eq '/' ) {
        return 'root';
    }

    # Find the element using the container directory
    my $orig_path = $path;
    $path =~ s{/([^/]+)$}{}xms;
    my $item_name = $1;

    if ( !$item_name ) {
        return 'root';
    }

    my $children = $self->{'gd'}->children($path);
    if ( !$children ) {
        die Cpanel::Transport::Exception->new( \@_, 0, "Error finding '$path': Does not exist" );
    }

    my $found_id;
    foreach my $child ( @{$children} ) {
        next if $child->name() ne $item_name;
        next if $cb && !$cb->($child);

        if ($found_id) {
            die Cpanel::Transport::Exception->new( \@_, 0, "Error finding '$orig_path': Multiple matches" );
        }

        $found_id = $child->id();
    }

    if ( !$found_id ) {
        die Cpanel::Transport::Exception->new( \@_, 0, "Error finding '$orig_path': Not found" );
    }

    return $found_id;
}

1;
