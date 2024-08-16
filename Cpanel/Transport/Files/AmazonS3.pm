
# cpanel - Cpanel/Transport/Files/AmazonS3.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Transport::Files::AmazonS3;

use strict;
use File::Spec                  ();
use Cpanel::Transport::Response ();
use File::Basename              ();
use Cpanel::Locale              ();
use Cpanel::Transport::Files    ();

our @ISA = ('Cpanel::Transport::Files');
my $locale;

sub new {
    my ( $class, $OPTS, $CFG ) = @_;
    $locale ||= Cpanel::Locale->get_handle();

    Cpanel::Transport::Files::load_module('Amazon::S3');

    $OPTS->{'s3'}         = _server_login($OPTS);
    $OPTS->{'bucket_obj'} = $OPTS->{'s3'}->bucket( $OPTS->{'bucket'} );

    # Only all adjust_region for Amazon, this isn't valid for non-Amazon S3 providers
    # Host will only be specified if we are not using Amazon
    if ( !exists $OPTS->{'host'} ) {
        $OPTS->{'s3'}->adjust_region( $OPTS->{'bucket'} );
    }

    # The size we break the file into for multipart upload
    # We hardcode this for now; but we may make this a config
    # option if there is demand for it.
    $OPTS->{'upload_chunk_size'} = 20 * 1024**2;

    my $self = bless $OPTS, $class;
    $self->{'config'} = $CFG;

    return $self;
}

sub _missing_parameters {
    my ($param_hashref) = @_;

    my @result = ();
    foreach my $key (qw/aws_access_key_id password bucket/) {
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

sub _get_valid_parameters {
    return qw/aws_access_key_id password bucket folder timeout/;
}

sub get_path {
    my ($self) = @_;

    # We need to use an absolute path on the remote machine because we
    # cannot be certain that we are in the root directory, since the root
    # directory might not be a valid location.  See case 70513.
    return "/$self->{'folder'}";
}

sub _validate_parameters {
    my ($param_hashref) = @_;
    my @result = ();

    foreach my $key (qw/aws_access_key_id password bucket/) {
        if ( !defined $param_hashref->{$key} ) {
            push @result, $key;
        }
    }

    push @result, 'timeout' unless Cpanel::Transport::Files::value_is_in_range( value => $param_hashref->{'timeout'}, min => 1, max => 300 );

    return @result;
}

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

    my $amazon_s3_params = {
        'aws_access_key_id'     => $OPTS->{'aws_access_key_id'},
        'aws_secret_access_key' => $OPTS->{'password'},
        'retry'                 => 1,
        'secure'                => 1,
    };

    # This will override the Amazon default host
    # Only non-Amazon S3 providers will supply their own host
    if ( exists $OPTS->{'host'} ) {
        $amazon_s3_params->{'host'} = $OPTS->{'host'};
    }

    my $s3 = Amazon::S3->new($amazon_s3_params);

    # If we did not create it, die
    if ( !$s3 ) {
        die Cpanel::Transport::Exception::Network::Authentication->new(
            \@_, 0,
            $locale->maketext('Could not connect to Amazon S3')
        );
    }

    return $s3;
}

#
# Remove leading/trailing/double slashes from path
#
sub _sanitize_remote_path {
    my ($path) = @_;

    # Break up the path pieces & remove an blanks due to leading/trailing/double slashes
    my @chunks = grep { $_ } File::Spec->splitdir($path);

    # Put the path chunks back together - minus the detrius
    return File::Spec->catdir(@chunks);
}

#
# Extract the error info from the s3 object
#
sub _error_msg {
    my ($self) = @_;

    return ( $self->{'s3'}->err || '' ) . ": " . ( $self->{'s3'}->errstr || '' );
}

#
# We put this in a separate function for unit testing purposes
#
sub _get_file_size {
    my ($file) = @_;

    return ( -s $file || 0 );
}

sub _put {    ## no critic(RequireArgUnpacking) - wrongly getting the perlcritic "unpack" error
    my ( $self, $local, $remote ) = @_;

    $remote = _sanitize_remote_path($remote);

    # If a file is over a threshold, we use the multipart API to upload the file.
    # Where as Amazon has a hard requirement to use the multipart API for files
    # 5Gb or greater, we found the multipart api is less prone to error for
    # uploading large files in a lower bandwidth situation.
    # (In particular, sending files to a geographicaly distant S3 bucket.)
    # So, if the file size is larger than a single chunk used in a
    # multipart upload, then use the multipart upload
    my $file_size = _get_file_size($local);
    if ( $file_size > $self->{'upload_chunk_size'} ) {
        my $chunk_size = $self->{'upload_chunk_size'};

        # Amazon only allows 10,000 chunks in a multipart upload
        # So, if the file is bigger than 10,000 times our chunk size
        # then we'll just increase the chunk size.
        my $max_size = 10_000 * $self->{'upload_chunk_size'};
        if ( $file_size > $max_size ) {

            # Ensure that we'll never have more than 10,000 parts by making the
            # chunk slightly larger.
            $chunk_size = ( $file_size / 10_000 ) + 1;
        }

        my ( $res, $msg ) = $self->_do_multipart_upload( $local, $remote, $chunk_size );

        if ($res) {
            return Cpanel::Transport::Response->new( \@_, 1, 'OK' );
        }
        else {
            die Cpanel::Transport::Exception->new( \@_, 0, $msg );
        }
    }
    elsif ( $file_size == 0 ) {

        # Amazon S3 does not allow zero-size files, upload a single byte instead
        if ( $self->{'bucket_obj'}->add_key( $remote, "\x00" ) ) {

            return Cpanel::Transport::Response->new( \@_, 1, 'OK' );
        }

        die Cpanel::Transport::Exception->new( \@_, 0, $self->_error_msg() );
    }
    elsif ( $self->{'bucket_obj'}->add_key_filename( $remote, $local ) ) {

        # If less then 5Gb, use the normal put operation to upload it
        return Cpanel::Transport::Response->new( \@_, 1, 'OK' );
    }
    else {
        die Cpanel::Transport::Exception->new( \@_, 0, $self->_error_msg() );
    }
}

#
# Amazon requires that objects larger than 5Gb be uploaded
# in chunks via the multipart upload API
#
sub _do_multipart_upload {
    my ( $self, $local, $remote, $chunk_size ) = @_;

    my $bucket = $self->{'bucket_obj'};

    # Start multipart transfer
    my $upload_id;
    eval { $upload_id = $bucket->initiate_multipart_upload($remote); };

    # initiate will die if it fails; but, we also want to verify
    # that we got an actual return value as well (in case AWS's response was malformed)
    return ( 0, "Failure in initiate_multipart_upload: $@" ) if $@;
    return ( 0, "Unable to initiate multipart upload" ) unless $upload_id;

    # Now handle the file upload
    my $fh;
    eval {
        open( $fh, '<', $local ) or die "Could not open $local: $!";
        binmode($fh)             or die "Could not set $local to binary mode:  $!";

        my $part_num = 1;
        my ( $buffer, $length, %parts_hash );

        while ( ( $length = read( $fh, $buffer, $chunk_size ) ) != 0 ) {

            # Upload the chunk we just read
            my $etag = $bucket->upload_part_of_multipart_upload( $remote, $upload_id, $part_num, $buffer, $length );

            # We should get an etag back as an acknowlegement of the upload
            die "Error uploading part $part_num of $local" unless $etag;

            # Save the etag, we'll need to send a hash of part_numbers => etags
            # when we want to complete the upload process
            $parts_hash{ $part_num++ } = $etag;
        }

        # read will return undef if there is an error (vs zero for end of file)
        die "Failure reading $local:  $!" unless defined $length;

        close($fh);

        # Notify Amazon of the completion of the file upload
        $bucket->complete_multipart_upload( $remote, $upload_id, \%parts_hash )
          or die "Unable to finalize the file upload";
    };
    if ($@) {
        close($fh) if $fh;
        my $error_message = $@;

        # Abort the upload operation if a failure occurred somewhere
        eval { $bucket->abort_multipart_upload( $remote, $upload_id ); };
        if ($@) {
            $error_message .= '; And error aborting upload:  ' . $@;
        }

        return ( 0, $error_message );
    }

    return ( 1, 'OK' );
}

sub _get {    ## no critic(RequireArgUnpacking) - wrongly getting the perlcritic "unpack" error
    my ( $self, $remote, $local ) = @_;

    $remote = _sanitize_remote_path($remote);

    if ( $self->{'bucket_obj'}->get_key_filename( $remote, 'GET', $local ) ) {
        return Cpanel::Transport::Response->new( \@_, 1, 'OK' );
    }
    else {
        die Cpanel::Transport::Exception->new( \@_, 0, $self->_error_msg() );
    }
}

sub _find_keys_under_path {
    my ( $self, $path ) = @_;

    my @keys;
    my $params       = $path eq '/' ? {} : { prefix => $path };
    my $more_entries = 1;
    while ($more_entries) {
        my $res = $self->{'bucket_obj'}->list($params);
        push @keys, @{ $res->{'keys'} };
        last unless @{ $res->{'keys'} };
        $params->{marker} = $res->{'keys'}[-1]{'key'};
        $more_entries = $res->{'is_truncated'};
    }

    return \@keys;
}

#
# Attempt to list some of the files under the path and error
# out if this fails.  This is a validation check to ensure the
# credentials have privileges to list files along with being
# able to upload/download.  With S3 this check is necessary.
#
sub _ls_check {    ## no critic(RequireArgUnpacking) - wrongly getting the perlcritic "unpack" error
    my ( $self, $path ) = @_;

    $path = _sanitize_remote_path($path) . '/';

    my $params = $path eq '/' ? {} : { prefix => $path };
    my $res    = $self->{'bucket_obj'}->list($params);

    if ( !defined $res ) {
        die Cpanel::Transport::Exception->new( \@_, 0, $self->_error_msg() );
    }

    return Cpanel::Transport::Response->new( \@_, 1, 'OK' );
}

sub _ls {    ## no critic(RequireArgUnpacking) - wrongly getting the perlcritic "unpack" error
    my ( $self, $path ) = @_;

    $path = _sanitize_remote_path($path) . '/';

    my $keys = $self->_find_keys_under_path($path);

    my %contents;
    foreach my $item (@$keys) {

        # Slip the ones that dont math our path
        next unless ( !$path || $path eq '/' || $item->{'key'} =~ m/^$path/ );

        my $type = ( $item->{'size'} == 0 && $item->{'key'} =~ m|/$| ) ? 'd' : '-';
        $item->{'key'} =~ s/^$path//;

        # This can happen if the key and the path are equal
        next unless $item->{'key'};

        $contents{ $item->{'key'} } = {
            'type'  => $type,
            'owner' => $item->{'owner_displayname'},
            'size'  => $item->{'size'},
        };
    }

    # In Amazon S3, a file can be in a folder without the folder existing on it's own
    # This is kind of strange, we need to return the existence of these folders
    # The pruning code needs to find the container folders for old backups to delete
    # So, we are going to go through each item and, if need be, create parent items
    my @file_list = keys %contents;    # Get the keys before starting the loop; we'll be modding the hash in the loop
    foreach my $file (@file_list) {

        my $file_info = $contents{$file};

        # Go up the tree of parents until reaching the top
        my $parent = $file;
        while ( $parent = File::Basename::dirname($parent) and $parent ne '.' and $parent ne '/' ) {

            # Make sure it has a trailing slash, S3's folders have this
            $parent .= '/' unless $parent =~ m|/$|;

            # Skip if it is already there
            next if $contents{$parent};

            # Add an entry for the non-existent parent
            # The parent, will, of course, be a directory
            $contents{$parent} = {
                'type'  => 'd',
                'owner' => $file_info->{'owner'},
                'size'  => '0',
            };
        }
    }

    # Again, since Amazon S3 list gives all the items in the bucket,
    # Our list of items contains some stuff nested several layers deep.
    # We only want to return the immediate contents of the specified folder
    # We could filter this out until now since we needed to do the operation
    # above to get the parent folders of the nested items
    my @nested_items = grep { /\/.+$/ } keys %contents;
    delete @contents{@nested_items};

    # The output must look like the results of "ls -l" & contain perms for Historical Reasons
    my @ls = map { "$contents{$_}{'type'}rw-r--r-- X X X $contents{$_}{'size'} X X X $_" } sort keys %contents;

    my @response = map { $self->_parse_ls_response($_) } @ls;
    return Cpanel::Transport::Response::ls->new( \@_, 1, 'Ok', \@response );
}

sub _mkdir {    ## no critic(RequireArgUnpacking) - wrongly getting the perlcritic "unpack" error
    my ( $self, $path ) = @_;

    # Folders in Amazon S3 end with a slash
    $path = _sanitize_remote_path($path) . '/';

    # A folder, in Amazon S3, is a key ending in a '/' with no contents
    if ( $self->{'bucket_obj'}->add_key( $path, '' ) ) {
        return Cpanel::Transport::Response->new( \@_, 1, 'OK' );
    }
    else {
        die Cpanel::Transport::Exception->new( \@_, 0, $self->_error_msg() );
    }
}

sub _chdir {    ## no critic(RequireArgUnpacking) - wrongly getting the perlcritic "unpack" error
    my ($self) = @_;

    # This has no real meaning for this
    return Cpanel::Transport::Response->new( \@_, 1, 'OK' );
}

sub _rmdir {    ## no critic(RequireArgUnpacking) - wrongly getting the perlcritic "unpack" error
    my ( $self, $path ) = @_;

    # Folders in Amazon S3 end with a slash
    $path = _sanitize_remote_path($path) . '/';

    # Amazon S3 doesn't list contents of folders, just the whole bucket
    my $keys = $self->_find_keys_under_path($path);

    # Find all the keys "under" this one
    # Do a reverse sort so we delete the objects in the folder
    # before deleting the folder
    my @keys = reverse sort grep { $_ =~ m/^$path/ } map { $_->{'key'} } @$keys;

    foreach my $key (@keys) {

        $self->{'bucket_obj'}->delete_key($key)
          or die Cpanel::Transport::Exception->new( \@_, 0, $self->_error_msg() );
    }

    return Cpanel::Transport::Response->new( \@_, 1, 'OK' );
}

sub _delete {    ## no critic(RequireArgUnpacking) - wrongly getting the perlcritic "unpack" error
    my ( $self, $path ) = @_;

    $path = _sanitize_remote_path($path);

    $self->{'bucket_obj'}->delete_key($path)
      or die Cpanel::Transport::Exception->new( \@_, 0, $self->_error_msg() );

    return Cpanel::Transport::Response->new( \@_, 1, 'OK' );
}

sub _pwd {    ## no critic(RequireArgUnpacking) - wrongly getting the perlcritic "unpack" error
    my ($self) = @_;

    # This has no real meaning for this
    return Cpanel::Transport::Response->new( \@_, 1, 'OK', '/' );
}

1;
