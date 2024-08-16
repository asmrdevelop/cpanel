
# cpanel - Cpanel/Transport/Files/Backblaze.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Transport::Files::Backblaze;

use strict;
use warnings;

use parent 'Cpanel::Transport::Files';

use Cpanel::Encoder::URI        ();
use Cpanel::Transport::Files    ();
use Cpanel::Transport::Response ();
use Cpanel::JSON                ();
use Cpanel::Debug               ();
use Cpanel::Locale              ();
use Cpanel::FileUtils::Split    ();
use Cpanel::Autodie             ();

use HTTP::Headers  ();
use HTTP::Request  ();
use MIME::Base64   ();
use LWP::UserAgent ();
use Digest::SHA1   ();
use Try::Tiny;

our $base_url = 'https://api.backblazeb2.com';
our $locale;

# See https://www.backblaze.com/b2/docs/large_files.html
# Adjust these as needed if the API changes
our $small_file_size_limit = 5_000_000_000;         # 5GB
our $maxfile_size          = 10_000_000_000_000;    # 10TB

# Maximum number of times to retry a request
our $max_retry_attempts = 20;

my @err_regxps_to_retry = ( qr/^5\d\d$/, qr/^40[18]$/ );

=head1 NAME

Cpanel::Transport::Files::Backblaze

=head1 SYNOPSIS

This module is exclusively invoked via its superclass Cpanel::Transport::Files
within the backup transport code.

=head1 DESCRIPTION

This module implements the transport used to upload backups to Backblaze B2.

=head1 NOTES

https://www.backblaze.com/b2/docs/

The Backblaze B2 API has many constraints that we needed to conform to.  Here is
an incomplete list of constraints and other concerns.

* We need an authorization token to interact with Backblaze, _get_authorization_token

* We need a special token to upload a file, b2_start_large_file, b2_get_upload_part_url,
  b2_get_upload_url.  These are needed for each file uploading.

* The maximum file size of any file is 5GB, in this case we break those files up
  into a manifest, and multiple parts.

* Internal jargon:

* large file: a file that should be uploaded in smaller chunks, but it will
  remain that same file when it arrives up on Backblaze.

* huge file: a file that is too large to be stored as a single file on
  Backblaze, it will be stored as a manifest and a number of parts.

* We want to make sure we upload a large file in chunks rather than as a whole
  because that will conserve memory, we do not want to load a 4GB file into memory
  to upload it.

  To implement this, we took advantage of the backblaze large file upload protocol

  b2_start_large_file
  b2_get_upload_part_url, and use that url to upload the chunks one at a time
  b2_finish_large_file

* At anytime in a file upload, b2 could redirect us to a new url, we get a 503 or
  401 error to make us reauthorize

* Backblaze does not have "directories", every file is a single file.  It allows slashes
  in the file name.   The list files b2 api does "respect" slashes as if they are directories.

=head1 SUBROUTINES

=head2 new

Instantiate a new instance

=cut

sub new {
    my ( $class, $OPTS ) = @_;

    $locale ||= Cpanel::Locale->get_handle();
    _check_host($OPTS);

    my $self = {%$OPTS};
    bless $self, $class;

    return $self;
}

=head2 _error

Instead of dies scattered around we funnel them all to here.

=cut

sub _error {
    my ( $self, $exception_type, $exception_params ) = @_;

    require Cpanel::Exception;
    die Cpanel::Exception::create( $exception_type, $exception_params );
}

=head2 _missing_parameters

Are there any required parameters that were not passed?

=cut

sub _missing_parameters {
    my ($param_hashref) = @_;

    $param_hashref->{'path'}    //= '';
    $param_hashref->{'timeout'} //= 180;
    return grep { !defined $param_hashref->{$_} } _get_valid_parameters();
}

=head2 _get_valid_parameters

These are the valid parameters

=cut

sub _get_valid_parameters {
    return qw/application_key_id application_key bucket_id bucket_name path timeout/;
}

=head2 _validate_parameters

Validate that the passed in parameters are correct.

=cut

sub _validate_parameters {
    my ($param_hashref) = @_;

    my @invalid = grep { !defined $param_hashref->{$_} || ( $_ ne 'path' && $param_hashref->{$_} eq '' ) } _get_valid_parameters();
    push @invalid, 'timeout' if !Cpanel::Transport::Files::value_is_in_range( value => $param_hashref->{'timeout'}, min => 1, max => 300 );
    my $bucket_name_length = length $param_hashref->{'bucket_name'};
    push @invalid, 'bucket_name' if $bucket_name_length < 6 || $bucket_name_length > 50;

    return @invalid;
}

=head2 _check_host

Evaluate all the parameters in one routine

=cut

sub _check_host {    ## no critic(RequireArgUnpacking) - passing all args for exception
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

    return;
}

=head2 _init

Initialize required object data

=cut

sub _init {
    my ($self) = @_;

    return if ( $self->{'initted'} );

    $self->{'path'} .= '/' if ( $self->{'path'} ne '' && substr( $self->{'path'}, -1 ) ne '/' );
    $self->{'cwd'}     = "";
    $self->{'initted'} = 1;

    return;
}

=head2 _do_request

_do_request() - Make a request to b2 api. Automagically retry on auth token expiry.

 %args:
   api_method     => (REQUIRED) call to execute
   api_url        => (OPTIONAL) URL to the api endpoint. Defaults to $self->{'api_url'}
   api_ver        => (OPTIONAL) version of the api. Defaults to v1
   custom_url     => (OPTIONAL) URL to use for an upload/download. Overrides api_method, api_url and api_ver.
   content_type   => (OPTIONAL) Custom content type. Defaults to application/json.
   payload        => (OPTIONAL) Whatever you want to POST up.
   authorization  => (OPTIONAL) custom Authorizaton header line. Defaults to the auth token.
   lives_on_error => (OPTIONAL) Whether or not to die when you encounter error. Falsey == die, and thus the default
   request_type   => (OPTIONAL) What type of request it is (GET, POST, etc.). Defaults to POST.

 Returns:
   HTTP::Response object.

=cut

my $ua;

sub _do_request {
    my ( $self, %args ) = @_;
    $self->_error( "MissingParameters", { 'names' => [ 'api_method', 'custom_url' ] } ) if !grep { defined $args{$_} } qw{api_method custom_url};
    $args{'content_type'}  ||= 'application/json';
    $args{'api_ver'}       ||= 'v1';
    $args{'request_type'}  ||= 'POST';
    $args{'authorization'} ||= $self->{'authorization_data'}->{'authorizationToken'};
    $args{'api_url'}       ||= $self->{'apiUrl'};
    $args{'extra_headers'} ||= {};

    my $headers = HTTP::Headers->new(
        'Authorization' => $args{'authorization'},
        %{ $args{'extra_headers'} },
    );
    $headers->header( 'Content-Type' => $args{'content_type'} ) if $args{'request_type'} eq 'POST';

    my $url     = $args{'custom_url'} ? $args{'custom_url'} : "$args{'api_url'}/b2api/$args{'api_ver'}/$args{'api_method'}";
    my $request = HTTP::Request->new( $args{'request_type'}, $url, $headers );

    #_debug( 'Request: ' . $request->as_string );
    $request->content( $args{'payload'} ) if $args{'payload'};

    my @request_suffix = $args{'file'} ? ( $args{'file'} ) : ();

    $ua ||= LWP::UserAgent->new( 'timeout' => $self->{'timeout'} );
    my $response = $ua->request( $request, @request_suffix );

    for ( 1 .. $max_retry_attempts ) {

        last if $response->is_success;

        # BackBlaze specifies that the proper way to handle these
        # error codes is to retry the request
        last if !( grep { $response->code == $_ } qw{503 500 401} );

        # Backblaze recommends small delay before retry
        sleep 5;

        # A 401 response code means our authorization has expired
        # and we need to get a new authorization token.
        # An api_method of b2_authorize_account means we are trying to
        # get authorization, so need to call _get_authorize_token,
        # just retry the request.
        if ( $response->code == 401 && $args{'api_method'} ne 'b2_authorize_account' ) {
            $self->_get_authorize_token(1);    # Use the force, as auth is expired
        }

        $response = $ua->request( $request, @request_suffix );

        # One retry should be sufficient per 401 error
        # Multiple 401 retries in succession may trigger brute force protection
        last if ( $response->code == 401 );
    }

    if ( !$response->is_success ) {

        # If it isn't just token expiry, die, as we don't know what to do about that
        $self->_error( "HTTP::Network", { 'error' => "CODE :" . $response->code . ": MSG :" . $response->status_line . ": " . $response->content, 'method' => $args{'request_type'}, 'url' => $url } ) unless $args{'lives_on_error'};
    }

    # Allow the caller to figure out what they want the decoded_content or content raw, etc.
    # by returning the response instead of the content.
    #_debug( 'Response: ' . $response->as_string );
    return $response;
}

=head2 _get_authorize_token

To start a session of uploads and/or downloads, we need to get an
authorization token.

=cut

sub _get_authorize_token {
    my ( $self, $force ) = @_;

    $self->_init();
    _debug("Forcibly regenerating authorize token!") if $force;
    return                                           if ( exists $self->{'authorization_data'} && !$force );

    my $credentials = MIME::Base64::encode_base64( $self->{'application_key_id'} . ':' . $self->{'application_key'} );
    my $response    = $self->_do_request( 'api_method' => 'b2_authorize_account', 'api_url' => $base_url, 'request_type' => 'GET', 'authorization' => "Basic $credentials" );
    $self->{'authorization_data'} = Cpanel::JSON::Load( $response->content );

    $self->_validate_token_or_die();
    $self->{'apiUrl'} = $self->{'authorization_data'}->{'apiUrl'};

    return;
}

=head2 _validate_token_or_die

We need to validate the data that came back from Backblaze to make sure
all the information we need is present.

=cut

# Token is optional
sub _validate_token_or_die {
    my ( $self, $token ) = @_;
    $token ||= $self->{'authorization_data'};
    $self->_error("AuthenticationFailed") if !exists $token->{'authorizationToken'};
    $self->_error( "MissingParameter", { 'name' => 'recommendedPartSize' } ) if !exists $token->{'recommendedPartSize'};
    $self->_error( "MissingParameter", { 'name' => 'apiUrl' } )              if !exists $token->{'apiUrl'};
    return;
}

=head2 _calc_sha1_digest

$fullpath - the file to calculate the sha1 digest for.

$part_offset - seek to this location before calculating, if present.

=cut

sub _calc_sha1_digest {
    my ( $self, $fullpath, $part_offset ) = @_;

    my $digest = Digest::SHA1->new();

    my $fh;
    if ( open $fh, '<', $fullpath ) {
        my $buffer;
        seek $fh, $part_offset, 0 if ($part_offset);
        while ( read( $fh, $buffer, 1024 ) ) {
            $digest->add($buffer);
        }
        close $fh;
    }
    else {
        $self->_error( "IO::FileOpenError", { 'path' => $fullpath, 'error' => $! } );
    }

    return $digest->hexdigest;
}

=head2 _get_upload_url

$force_new_token - optional parameter: throw away existing token if present and reauthorize.

In order to upload a file we need to get both the url to upload it to as well as a upload
authorization token.

Returns the url.
It also updates the object with the authorization token.

=cut

sub _get_upload_url {
    my ( $self, $force_new_token ) = @_;

    return if ( $self->{'upload_url'} && !$force_new_token );

    my $bucket_id = $self->{'bucket_id'};

    my $content_hr = { 'bucketId' => $bucket_id };
    my $content    = Cpanel::JSON::Dump($content_hr);

    my $response      = $self->_do_request( 'api_method' => 'b2_get_upload_url', 'payload' => $content );
    my $response_data = Cpanel::JSON::Load( $response->content );

    $self->{'upload_url'} = $response_data->{'uploadUrl'};

    # Check that the token looks right
    $self->{'upload_auth_token'} = $response_data->{'authorizationToken'};

    return;
}

=head2 _get_file_info

$local_fname - File to get stat information from.

Stat the file and return a hash ref of the information we will store with Backblaze.

=cut

sub _get_file_info {
    my ($local_fname) = @_;

    my ( $dev, $ino, $mode, $nlink, $uid, $gid, $rdev, $size, $atime, $mtime, $ctime, $blksize, $blocks ) = stat($local_fname);

    my $file_info = {
        'mode'  => "$mode",
        'uid'   => "$uid",
        'gid'   => "$gid",
        'mtime' => "$mtime",
        'size'  => "$size",
    };

    return $file_info;
}

=head2 _get_start_large_file

$remote          - Name of the file when on Backblaze.

$local_fname     - The local file to upload

$this_file_size  - Optional: override the file size (for mostly huge file uploads).

Notify Backblaze we are about to upload a large file in multiple chunks.

Returns a hash ref of information needed for the subsequent api calls.

=cut

sub _get_start_large_file {
    my ( $self, $remote, $local_fname, $this_file_size ) = @_;

    return if ( $self->{'large'} );

    my $fh;
    my $extra_headers = {};
    my $mtime         = ( stat($local_fname) )[9];
    $extra_headers->{'X-Bz-Info-src_last_modified_millis'} = $mtime . '000';

    my $fileInfo = _get_file_info($local_fname);
    $fileInfo->{'size'} = "$this_file_size" if ($this_file_size);

    my $content_hr = {
        'bucketId'    => "$self->{'bucket_id'}",
        'fileName'    => "$remote",
        'contentType' => 'application/octet-stream',
        'fileInfo'    => $fileInfo,
    };

    my $response = $self->_do_request( 'api_method' => 'b2_start_large_file', 'extra_headers' => $extra_headers, 'payload' => Cpanel::JSON::Dump($content_hr) );
    return Cpanel::JSON::Load( $response->content );
}

=head2 _get_finish_large_file

$large_file_info - a hash ref with the information about the large file operation
                   this comes from b2_start_large_file

$sha_ra          - as we upload each chunk we need to record the sha1 of each chunk
                   and send them back up on finish so Backblaze can validate that
                   the file completed correctly.

When we are done uploading the chunks of a large file, we send up the list of sha's
that we sent up with each chunk.  This closes out the large file upload operation.

=cut

sub _get_finish_large_file {
    my ( $self, $large_file_info, $sha_ar ) = @_;

    my $content_hr = {
        'fileId'        => $large_file_info->{'fileId'},
        'partSha1Array' => $sha_ar,
    };

    my $content = Cpanel::JSON::Dump($content_hr);

    my $response = $self->_do_request(
        'api_method'     => 'b2_finish_large_file',
        'payload'        => $content,
        'lives_on_error' => 1,
    );

    # We never actually check the content if this succeeds.
    # If we ever did in the future, we'd want to decode the JSON
    return if $response->is_success;

    # OK, so if it fails, we'll want to check the 'b2_get_file_info' call,
    # as apparently per B2, finish_large_file could have failed but the file
    # actually got finished. As such, attempt to get the "file info", as it
    # will return 200 if OK then.
    _debug( "b2_finish_large_file failed: " . $response->status_line . "; running b2_get_file_info to check on things..." );
    my $check_resp = $self->_do_request(
        'api_method' => 'b2_get_file_info',
        'payload'    => {
            'fileId' => $large_file_info->{'fileId'},
        },
        'lives_on_error' => 1,
    );

    # OK, so if *this* failed as well, we should just bail out with the error
    # message we got earlier from the 'b2_finish_large_file' call, as that's
    # probably gonna be the better error message in this case.
    if ( !$check_resp->is_success ) {
        _debug( "b2_get_file_info failed to get info for file ID $large_file_info->{'fileId'}: " . $check_resp->status_line . "; Stopping here." );
        $self->_error(
            "HTTP::Network",
            {
                'error'  => "CODE :" . $response->code . ": MSG :" . $response->status_line . ": " . $response->content,
                'method' => 'POST',
                'url'    => "$self->{'apiUrl'}/b2api/v1/b2_finish_large_file",
            },
        );
    }

    return;
}

# Get all the Debug info you want by setting CPANEL_DEBUG_LEVEL env var
sub _debug {
    my ( $msg, $data ) = @_;
    return if !$Cpanel::Debug::level;
    $msg ||= "";
    $msg .= "\n";
    require Data::Dumper;
    $msg .= "Debug Dump: " . Data::Dumper::Dumper($data) if $data;
    print STDERR $msg;
    return;
}

=head2 _get_upload_part_url

$fileId - comes from the _get_start_large_file

Get the url and auth token to upload the large file.

=cut

sub _get_upload_part_url {
    my ( $self, $fileId ) = @_;

    my $content_hr = { 'fileId' => $fileId };
    my $content    = Cpanel::JSON::Dump($content_hr);

    my $response      = $self->_do_request( 'api_method' => 'b2_get_upload_part_url', 'payload' => $content );
    my $response_data = Cpanel::JSON::Load( $response->content );

    $self->{'upload_part_url'} = $response_data->{'uploadUrl'};

    $self->{'upload_part_auth_token'} = $response_data->{'authorizationToken'};

    return;
}

=head2 _put_large_file

$local          - the local file

$remote_wo_cwd  - the remote file name without the presence of the cwd in the path

$size           - size of the file

If the _put method identifies that it is uploading a "huge file" it calls this method
to break the file up into parts.  It then uses _put to upload the manifest and each
part.

=cut

sub _put_large_file {    ## no critic(RequireArgUnpacking)
    my ( $self, $local, $remote_wo_cwd, $size ) = @_;    # perl critic error

    # Maximum number of chunks is 10k per the API (indexed starting at 1), so divvy it up based on that to start with
    # but attempt to use the 'recommendedPartSize' if it looks sane to do so
    my $chunk_size = $size / 10000;
    $chunk_size = $self->{'authorization_data'}{'absoluteMinimumPartSize'} if $chunk_size < $self->{'authorization_data'}{'absoluteMinimumPartSize'};
    $chunk_size = $self->{'authorization_data'}{'recommendedPartSize'}     if ( $self->{'authorization_data'}{'recommendedPartSize'} && $chunk_size < $self->{'authorization_data'}{'recommendedPartSize'} );

    my $splitter = Cpanel::FileUtils::Split->new( 'file' => $local, 'part_size' => $size, 'chunk_size' => $chunk_size );

    # Now let's upload all the parts via chunked upload.
    my $large_file_info;
    my @sha_ar;
    my $pre_part_processor = sub {
        my %opts = @_;
        _debug("_put_large_file: Attempting to start upload of $local");
        $large_file_info = $self->_get_start_large_file( $remote_wo_cwd, $local, $size );
        $self->_get_upload_part_url( $large_file_info->{'fileId'} );
        @sha_ar = ();
        return;
    };
    my $chunk_processor = sub {
        my %opts = @_;

        my $digest = Digest::SHA1->new();
        $digest->add( $opts{'chunk'} );
        my $sha1 = $digest->hexdigest();
        push @sha_ar, $sha1;

        my $extra_headers = {
            'fileId'            => $large_file_info->{'fileId'},
            'X-Bz-Part-Number'  => $opts{'chunk_num'},
            'Content-Length'    => $opts{'chunk_size'},
            'X-Bz-Content-Sha1' => $sha1,
        };

        my $tries = 1;

        # This is set to a default value due to using it outside of the loop
        # below. Logically, you won't ever need this set to a value in
        # practice. However, in some contexts like a unit test, not setting
        # this could lead to uninitialized value on concat warnings depending
        # on how you setup your mocks. As such I set it here, as there's
        # really no huge penalty for doing so.
        my $status_line = "599 UNKNOWN";

        # Retry up to 10x on known errors
        while ( $tries < 10 ) {

            # Maybe letting it cool off for 5s will help when we're constantly failing.
            if ( $tries > 5 ) {
                _debug("Waiting 5s for things to stabilize...");
                sleep 5;
            }
            _debug("_put_hugefile_driver: Attempting upload of chunk #$opts{'chunk_num'} (chunk size of $opts{'chunk_size'}) -- Upload attempt #$tries...");

            my $response = $self->_do_request(
                'authorization'  => $self->{'upload_part_auth_token'},
                'custom_url'     => $self->{'upload_part_url'},
                'payload'        => $opts{'chunk'},
                'content_type'   => 'application/octet-stream',
                'extra_headers'  => $extra_headers,
                'lives_on_error' => 1,
            );

            last if ( $response->is_success );

            # See https://www.backblaze.com/b2/docs/uploading.html
            # Retry any 5xx errors, any 408 Request Timeout and any 401 expired_auth_token

            $status_line = $response->status_line;
            $self->_error( "HTTP::Network", { 'error' => $status_line, 'method' => 'POST', 'url' => $self->{'upload_part_url'} } ) if ( !grep { $response->code =~ $_ } @err_regxps_to_retry );

            my $err_str = "Upload attempt failed for file chunk #$opts{'chunk_num'} (chunk size of $opts{'chunk_size'}).\n";
            $err_str .= "Error we got back from the server was '" . $status_line . "' when uploading to '$self->{'upload_part_url'}'.\n";
            $err_str .= "Since this is a re-tryable error per Backblaze, we will re-try the request after obtaining a new upload URL.\n";
            $err_str .= "See https://www.backblaze.com/b2/docs/uploading.html for more information...";
            _debug($err_str);

            # If the 401 is not from expired_token, then this won't work, but that's ultimately fine, as it'll die in the below instance if that's the case after 3x retries
            $self->_get_upload_part_url( $large_file_info->{'fileId'} );
            _debug("Got new upload URL: $self->{'upload_part_url'}");

            $tries++;
        }
        $self->_error( "HTTP::Network", { 'error' => "$status_line after $tries attempts to upload the file chunk.", 'method' => 'POST', 'url' => $self->{'upload_part_url'} } ) if $tries >= 10;

        return;
    };
    my $post_part_processor = sub {
        my %opts = @_;
        _debug("_put_large_file: Attempting to finish upload of $local");
        $self->_get_finish_large_file( $large_file_info, \@sha_ar );
        return;
    };

    $splitter->process_parts( $pre_part_processor, $chunk_processor, $post_part_processor );

    return Cpanel::Transport::Response->new( \@_, 1, 'OK' );
}

=head2 _put_small

$local          - the local file

$remote         - the remote file name

$size           - size of the file

$part_offset    - if this is part of a huge file upload, this is where to seek to in the
                  local file.

If the _put method identifies that it is uploading a "small file" it calls this method
to handle it.

=cut

sub _put_small_file {
    my ( $self, $local, $remote, $size, $part_offset ) = @_;

    _debug("_put: Small file upload mode");
    $self->_get_upload_url();

    my $sha1;

    if ($part_offset) {
        $sha1 = $self->_calc_sha1_digest( $local, $part_offset );
    }
    else {
        $sha1 = $self->_calc_sha1_digest($local);
    }

    my $extra_headers = {
        'X-Bz-File-Name'    => Cpanel::Encoder::URI::uri_encode_str($remote),
        'Content-Length'    => $size,
        'X-Bz-Content-Sha1' => $sha1,
    };

    # a maximum of 10 X-Bz-Info headers are allowed.
    my $file_info = _get_file_info($local);
    $file_info->{'size'} = $size;
    foreach my $key ( keys %{$file_info} ) {
        $extra_headers->{ 'X-Bz-Info-' . $key } = $file_info->{$key};
    }

    open( my $fh, '<', $local ) or $self->_error( "IO::FileOpenError", { 'path' => $local, 'error' => $! } );
    my $mtime = ( stat($fh) )[9];
    $extra_headers->{'X-Bz-Info-src_last_modified_millis'} = $mtime . '000';

    # used during huge file uploads
    seek $fh, $part_offset, 0 if ( $part_offset > 0 );

    my $totalbytes = 0;
    my $processor  = sub {
        my $buffer;
        my $bytes = Cpanel::Autodie::read( $fh, $buffer, 1024 );
        return $bytes ? $buffer : undef;
    };

    my $response = $self->_do_request(
        'authorization'  => $self->{'upload_auth_token'},
        'custom_url'     => $self->{'upload_url'},
        'payload'        => $processor,
        'content_type'   => 'application/octet-stream',
        'extra_headers'  => $extra_headers,
        'lives_on_error' => 1,
    );

    close $fh;

    if ( !$response->is_success() ) {
        if ( grep { $response->code =~ $_ } @err_regxps_to_retry ) {
            _debug("SERVICE BUSY GET NEW TOKEN");
            $self->_get_upload_url(1);
            return $self->_put( $local, $remote );
        }
        $self->_error( "HTTP::Network", { 'error' => "CODE :" . $response->code . ": MSG :" . $response->status_line . ":", 'method' => 'POST', 'url' => $self->{'upload_url'} } );
    }

    return;
}

=head2 _put

$local          - the local file

$remote         - the remote file

$hugefile_hr    - if this is present, we are in the middle of a hugefile upload

_put handles uploading a file to Backblaze, it deals with small, large and hugefiles.

=cut

sub _put {    ## no critic(RequireArgUnpacking)
    my ( $self, $local, $remote, $hugefile_hr ) = @_;    # perl critic error

    $self->_get_authorize_token();
    my $remote_wo_cwd = $remote;
    my $size          = -s $local;

    if ( $size > $maxfile_size ) {
        return Cpanel::Transport::Response->new( \@_, 0, 'Maximum upload filesize for BackBlaze B2 is 10TB' );
    }

    # This file is larger than the B2 file size limit
    # We need to break it up into parts so each no larger
    # than the file size limit of 5GB
    return $self->_put_large_file( $local, $remote_wo_cwd, $size ) if ( $size > $small_file_size_limit );

    # otherwise, it is a small file, just upload it, lol
    $self->_put_small_file( $local, $remote, $size, 0 );
    return Cpanel::Transport::Response->new( \@_, 1, 'OK' );
}

=head2 _get

$local          - the local file

$remote         - the remote file

Download the remote file to the local file.

=cut

sub _get {    ## no critic(RequireArgUnpacking)
    my ( $self, $remote, $local ) = @_;    # perl critic error

    $self->_get_authorize_token();

    my $remote_wo_cwd = $remote;

    my $download_url = $self->{'authorization_data'}->{'downloadUrl'} . '/file/' . $self->{'bucket_name'} . '/' . $remote;
    _debug("Download url :$download_url:");
    my $response = $self->_do_request( 'custom_url' => $download_url, 'request_type' => 'GET', 'file' => $local, 'lives_on_error' => 1 );
    if ( $response->code == 404 ) {

        # Even though we don't do these kinds of uploads anymore, allow them
        # to be re-downloaded
        if ( $local =~ m/\._b2_manifest$/ ) {

            # we failed to find a manifest
            return Cpanel::Transport::Response->new( \@_, 0, 'File not found' );
        }

        # this might be a "huge" file, so check to see if we see a manifest
        # file or not.

        my $manifest_local  = $local . '._b2_manifest';
        my $manifest_remote = $remote_wo_cwd . '._b2_manifest';

        my $cpresponse = $self->_get( $manifest_remote, $manifest_local );
        if ( !$cpresponse->success() ) {
            return Cpanel::Transport::Response->new( \@_, 0, 'File not found' );
        }

        my $manifest_hr = Cpanel::JSON::LoadFile($manifest_local);
        unlink $manifest_local;
        _debug( "Got manifest:", $manifest_hr );

        my $fh;
        if ( !open $fh, '>', $local ) {
            $self->_error( "IO::FileOpenError", { 'path' => $local, 'error' => $! } );
        }

        foreach my $idx ( 1 .. $manifest_hr->{'num_parts'} ) {
            my $remote_part = $remote_wo_cwd . '._b2_part_' . $idx;
            undef $cpresponse;
            try {
                $cpresponse = $self->_get(
                    $remote_part,
                    sub {
                        my ( $chunk, $response_obj, $protocol_obj ) = @_;
                        print $fh $chunk;
                    }
                );
            }
            catch {
                close $fh;
                die $_;    # can I rethrow this?
            };

            if ( !$cpresponse || !$cpresponse->success() ) {
                close $fh;
                return Cpanel::Transport::Response->new( \@_, 0, 'Error downloading file' );
            }
        }
        close $fh;
    }
    elsif ( $response->code != 200 ) {

        # If it isn't just token expiry, die, as we don't know what to do about that
        $self->_error( "HTTP::Network", { 'error' => "CODE :" . $response->code . ": MSG :" . $response->status_line . ": " . $response->content, 'method' => 'GET', 'url' => $download_url } );
    }

    return Cpanel::Transport::Response->new( \@_, 1, 'OK' );
}

=head2 _ls

$path           - The "directory" to get a list of files from.
$show_all       - optional, if set to 1, will show all files in path and below

Get a list of files.

=cut

sub _ls {    ## no critic(RequireArgUnpacking)
    my ( $self, $path, $show_all ) = @_;    # perl critic error

    $show_all //= 0;

    $self->_get_authorize_token();

    $path .= '/' if ( $path ne '' && substr( $path, -1 ) ne '/' );

    my $nextFileName;
    my @list_of_files;

    while (1) {
        my $content_hr = { 'bucketId' => $self->{'bucket_id'} };
        $content_hr->{'startFileName'} = $nextFileName if $nextFileName;

        if ( !$show_all ) {
            $content_hr->{'prefix'}    = $path;
            $content_hr->{'delimiter'} = '/';
        }

        my $content  = Cpanel::JSON::Dump($content_hr);
        my $response = $self->_do_request( 'api_ver' => 'v2', 'api_method' => 'b2_list_file_names', 'payload' => $content );

        my $response_data = Cpanel::JSON::Load( $response->content );

        my $files_ar = $response_data->{'files'};
        foreach my $file_hr ( @{$files_ar} ) {

            # after looking at what the Backup Transporter is expecting
            # we need to strip off $path

            my $filename = $file_hr->{'fileName'};
            if ( $path ne "" ) {
                if ( $filename =~ m/^$path/ ) {
                    $filename = substr( $filename, length($path) );
                }
            }

            my $detail_hr = { 'filename' => $filename };

            if ( $file_hr->{'action'} eq 'folder' ) {
                $detail_hr->{'type'}  = 'directory';
                $detail_hr->{'perms'} = -1;
                $detail_hr->{'size'}  = 0;
                $detail_hr->{'user'}  = 0;
                $detail_hr->{'group'} = 0;
            }
            else {
                $detail_hr->{'type'}   = 'file';
                $detail_hr->{'perms'}  = $file_hr->{'fileInfo'}->{'mode'};
                $detail_hr->{'size'}   = $file_hr->{'fileInfo'}->{'size'};
                $detail_hr->{'user'}   = $file_hr->{'fileInfo'}->{'uid'};
                $detail_hr->{'group'}  = $file_hr->{'fileInfo'}->{'gid'};
                $detail_hr->{'fileId'} = $file_hr->{'fileId'};
            }

            push( @list_of_files, $detail_hr );
        }

        last if ( !$response_data->{'nextFileName'} );
        $nextFileName = $response_data->{'nextFileName'};
    }

    return Cpanel::Transport::Response::ls->new( \@_, 1, 'OK', \@list_of_files );
}

=head2 _mkdir

This is a noop since Backblaze does not support directories.

=cut

sub _mkdir {
    my ( $self, $path ) = @_;
    return Cpanel::Transport::Response->new( \@_, 1, 'OK' );
}

=head2 _chdir

$path - where to "move to"

Backblaze does not support directories, so instead we keep an internal copy of the
cwd.

=cut

sub _chdir {    ## no critic(RequireArgUnpacking)
    my ( $self, $path ) = @_;    # perl critic error

    $self->_init();

    $path .= '/' if ( substr( $path, -1 ) ne '/' );
    $self->{'cwd'} = $path;

    return Cpanel::Transport::Response->new( \@_, 1, 'OK' );
}

=head2 _ls_one_file

$path - File to get the information about

This is used exclusively by the delete methods, it gets the file information
for the named file.   The delete methods need the fileId that is provided
from the ls api.

=cut

sub _ls_one_file {
    my ( $self, $path ) = @_;

    $self->_get_authorize_token();

    my $content_hr = { 'bucketId' => $self->{'bucket_id'} };
    $content_hr->{'prefix'} = $path;
    my $content = Cpanel::JSON::Dump($content_hr);

    my $response = $self->_do_request( 'api_ver' => 'v2', 'api_method' => 'b2_list_file_names', 'payload' => $content );

    my $response_data = Cpanel::JSON::Load( $response->content );

    my $file_hr = $response_data->{'files'}->[0];

    my $detail_hr = { 'filename' => $file_hr->{'fileName'} };

    if ( $file_hr->{'action'} eq 'folder' ) {
        $detail_hr->{'type'}  = 'directory';
        $detail_hr->{'perms'} = -1;
        $detail_hr->{'size'}  = 0;
        $detail_hr->{'user'}  = 0;
        $detail_hr->{'group'} = 0;
    }
    else {
        $detail_hr->{'type'}   = 'file';
        $detail_hr->{'perms'}  = $file_hr->{'fileInfo'}->{'mode'};
        $detail_hr->{'size'}   = $file_hr->{'fileInfo'}->{'size'};
        $detail_hr->{'user'}   = $file_hr->{'fileInfo'}->{'uid'};
        $detail_hr->{'group'}  = $file_hr->{'fileInfo'}->{'gid'};
        $detail_hr->{'fileId'} = $file_hr->{'fileId'};
    }

    return $detail_hr;
}

=head2 _delete_by_file_id

$path - filename to delete

$fileId - the fileId to delete, this is the key

Delete the file by the passed in id, the filename is also needed.

=cut

sub _delete_by_file_id {
    my ( $self, $path, $fileId ) = @_;

    $self->_get_authorize_token();

    my $content_hr = { 'fileName' => $path };
    $content_hr->{'fileId'} = $fileId;
    my $content = Cpanel::JSON::Dump($content_hr);

    my $response = $self->_do_request( 'api_ver' => 'v2', 'api_method' => 'b2_delete_file_version', 'payload' => $content );

    return;
}

=head2 _delete

$path - filename to delete

Delete a file by filename.

We have to call _ls_one_file to get the fileId and then call _delete_by_file_id

=cut

sub _delete {
    my ( $self, $path ) = @_;
    $self->_init();

    my $detail_hr = $self->_ls_one_file($path);
    _debug( "DELETE :$path: :" . $detail_hr->{'fileId'} . ":" );

    $self->_delete_by_file_id( $path, $detail_hr->{'fileId'} );

    return;
}

=head2 _rmdir

$path - directory to delete

Recursively delete the directory and all the files contained within it and below it.

=cut

sub _rmdir {    ## no critic(RequireArgUnpacking)
    my ( $self, $path ) = @_;    # perl critic error
    $self->_init();

    my $response = $self->_ls( "", 1 );
    my @files    = @{ $response->{'data'} };

    if ( $path eq "" ) {
        foreach my $file (@files) {
            next if ( $file->{'type'} eq 'directory' );
            $self->_delete_by_file_id( $file->{'filename'}, $file->{'fileId'} );
        }
    }
    else {
        my @del_files = grep { $_->{'filename'} =~ m/^$path/ } @files;
        foreach my $file (@del_files) {
            next if ( $file->{'type'} eq 'directory' );
            $self->_delete_by_file_id( $file->{'filename'}, $file->{'fileId'} );
        }
    }

    return Cpanel::Transport::Response->new( \@_, 1, 'OK' );
}

=head2 _rmdir

Returns the current working directory.

=cut

sub _pwd {
    my ($self) = @_;
    $self->_init();
    return Cpanel::Transport::Response->new( \@_, 1, 'OK', $self->{'cwd'} );
}

1;
