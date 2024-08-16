package Cpanel::HttpRequest;

# cpanel - Cpanel/HttpRequest.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::ArrayFunc::Shuffle        ();
use Cpanel::Crypt::GPG::Settings      ();
use Cpanel::FileUtils::Copy           ();
use Cpanel::Hostname                  ();
use Cpanel::Debug                     ();
use Cpanel::Rand::Get                 ();
use Cpanel::SocketIP                  ();
use Cpanel::URL                       ();
use Cpanel::UrlTools                  ();
use Cpanel::Encoder::Tiny             ();
use Cpanel::HTTP::Tiny::FastSSLVerify ();
use Socket                            ();

our $DEFAULT_TIMEOUT       = 260;
our $SIMULATE_FAILURE      = 0;
our $DEBUG                 = 0;
our $VERSION               = '3.0';
our $MAX_CONTENT_SIZE      = ( 1024 * 1024 * 1024 * 1024 );
our $HTTP_RETRY_COUNT      = 12;
our $SIGNATURE_RETRY_COUNT = 4;
our $MAX_RESOLVE_ATTEMPT   = 65;

my $buffer_size         = 131070;
my $has_cpanel_dnsRoots = 0;

sub new {
    my ( $obj, %OPTS ) = @_;

    my $self = bless {}, $obj;

    $self->{'connectedHostAddress'}   = '';                                                                #ip of connected host
    $self->{'connectedHostname'}      = '';                                                                #hostname of connected host
    $self->{'connectedHostFailCount'} = {};
    $self->{'connected'}              = 0;
    $self->{'http_retry_count'}       = $OPTS{'http_retry_count'} || $HTTP_RETRY_COUNT;
    $self->{'use_dns_cache'}          = exists $OPTS{'use_dns_cache'} ? int $OPTS{'use_dns_cache'} : 1;    #on by default
    $self->{'retry_dns'}              = exists $OPTS{'retry_dns'}     ? $OPTS{'retry_dns'}         : 1;
    $self->{'use_mirror_addr_list'}   = $OPTS{'use_mirror_addr_list'} || 0;
    $self->{'hideOutput'}             = $OPTS{'hideOutput'} && $OPTS{'hideOutput'} eq '1' ? 1 : 0;
    $self->{'htmlOutput'}             = $OPTS{'htmlOutput'} || 0;
    $self->{'dns_cache_ttl'}          = exists $OPTS{'dns_cache_ttl'} ? int $OPTS{'dns_cache_ttl'} : 7200;
    $self->{'mirror_search_attempts'} = {};
    $self->{'last_status'}            = undef;
    $self->{'die_on_404'}             = $OPTS{'die_on_404'}      || 0;
    $self->{'die_on_4xx_5xx'}         = $OPTS{'die_on_4xx_5xx'}  || 0;
    $self->{'die_on_error'}           = $OPTS{'die_on_error'}    || 0;
    $self->{'return_on_404'}          = $OPTS{'return_on_404'}   || 0;
    $self->{'return_on_error'}        = $OPTS{'return_on_error'} || 0;
    $self->{'protocol'}               = $OPTS{'protocol'}        || 0;
    $self->{'timeout'}                = $OPTS{'timeout'}         || $DEFAULT_TIMEOUT;
    $self->{'level'}                  = 0;
    $self->{'logger'}                 = $OPTS{'logger'};

    if ( !$self->{'logger'} ) {
        require Cpanel::Logger;
        $self->{'logger'} = Cpanel::Logger->new();
    }
    $self->{'announce_mirror'}       = $OPTS{'announce_mirror'};
    $self->{'signed'}                = $OPTS{'signed'};
    $self->{'vendor'}                = $OPTS{'vendor'}                || 'cpanel';
    $self->{'categories'}            = $OPTS{'categories'}            || Cpanel::Crypt::GPG::Settings::default_key_categories();
    $self->{'signature_validation'}  = $OPTS{'signature_validation'}  || Cpanel::Crypt::GPG::Settings::signature_validation_enabled();
    $self->{'signature_retry_count'} = $OPTS{'signature_retry_count'} || $SIGNATURE_RETRY_COUNT;

    $self->{'speed_test_enabled'} = exists $OPTS{'speed_test_enabled'} ? int( $OPTS{'speed_test_enabled'} ) : 1;
    $self->{'speed_test_file'}    = $OPTS{'speed_test_file'} || '/speedcheck';
    $self->{'sig_data'}           = undef;

    return $self;
}

sub _output {
    my ( $self, $str ) = @_;

    return if $self->{'hideOutput'};

    if ( $self->{'htmlOutput'} ) {
        $str = Cpanel::Encoder::Tiny::safe_html_encode_str($str);
        $str =~ s/\n/<br>/g;
    }

    return print $str;
}

sub request {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my ( $self, %OPTS ) = @_;

    # backward compatibility
    # Note that defined here is required for compatibility with 5.10.
    $OPTS{'uncompress'} = 1 if ( defined $OPTS{'uncompress_bzip2'} && length $OPTS{'uncompress_bzip2'} && $OPTS{'url'} =~ m{\.bz2$} );

    my $check_signature = defined $OPTS{'signed'} ? $OPTS{'signed'} : $self->{'signed'};
    my $uncompress      = ( defined $OPTS{'uncompress'} && length $OPTS{'uncompress'} && $OPTS{'uncompress'} && $OPTS{'url'} =~ m/\.(bz2|xz)$/ );

    # Do not check signatures if it is turned off.

    if ( !$self->{'signature_validation'} ) {
        $check_signature = undef;
    }

    # Do not check signatures if on a buildmachine.

    if ( Cpanel::Hostname::gethostname() =~ /^(autobuild|perlcc).*\.dev\.cpanel\.net$/ ) {
        $check_signature = undef;
    }

    # If we are not checking signature, use legacy request logic.

    if ( !$check_signature ) {
        return $self->_request_file(%OPTS);
    }

    # If we have not returned by now, we want to check the signature.
    # Initialize GPG object. Die on failure.
    # This is likely already loaded if we are called from Cpanel::Sync::v2
    my ( $gpg, $gpg_msg ) = $self->get_crypt_gpg_vendorkey_verify( vendor => $OPTS{'vendor'}, categories => $OPTS{'categories'} );

    if ( !$gpg ) {
        $self->_sigerror_die("Failed to create gpg object: $gpg_msg");
    }

    # Check if we were called with the 'destfile' option, and preserve for later use.
    # We need to delete this option otherwise signature downloads will fail.

    my $destfile = $OPTS{'destfile'};

    # Generate download and signature URLs.

    my $file_url = $OPTS{'url'};
    my $signature_url;

    if ( $OPTS{'signature_url'} ) {
        $signature_url = $OPTS{'signature_url'};
    }
    elsif ($destfile) {
        $signature_url = $file_url;

        # We assume we generated the signature on the base filename.
        $signature_url =~ s/\.bz2$//;    # xz files are not signed
        $signature_url = $signature_url . '.asc';
    }
    else {
        $signature_url = $file_url . '.asc';
    }

    my $signature_validation_failures = 0;
    my $signature_hostaddr;
    my $basefile_hostaddr;
    my $verification_data;
    my $verification_message;
    while ( $signature_validation_failures++ < $self->{'signature_retry_count'} ) {

        # This loop will only run one time if there is a definitive failure to download either
        # the file or the sinature since the _request_file() function will have tried all the
        # mirrors already
        #
        # If it manages to download both but the signature fails to validate, we will retry
        # up to three times.
        #
        # The retry will switch the mirrors if the file and signature were fetched from the same
        # mirror. If not, the assumption is that _request_file() switched mirrors
        # and both files should be retried starting from the current mirror.

        $OPTS{'url'} = $signature_url;
        delete $OPTS{'destfile'};
        my $signature_data = $self->_request_file(%OPTS);

        if ( !$signature_data ) {
            $self->_die( "Failed to download signature at URL 'http://" . $OPTS{'host'} . $signature_url . "'." );
        }
        $signature_hostaddr = $self->{'connectedHostAddress'};

        # Download and verify the file.

        if ($destfile) {
            if ( !$uncompress && $destfile =~ /\.(bz2|xz)$/ ) {
                my $compressed_ext = $1;

                # Compressed 'destfile' case.

                my $basename = $destfile;
                $basename =~ s/\.\Q$compressed_ext\E$//;

                my $tmp_file_a = $basename . '_' . Cpanel::Rand::Get::getranddata(8) . ".$compressed_ext";
                my $tmp_file_b = $basename . '_' . Cpanel::Rand::Get::getranddata(8) . ".$compressed_ext";

                $OPTS{'url'}      = $file_url;
                $OPTS{'destfile'} = $tmp_file_a;

                # In the 'destfile' case, _request_file() returns only the '$complete' value.
                # So, this is a valid check of whether or not the download succeeded, even if content is 0 bytes.

                my $req = $self->_request_file(%OPTS);

                if ( !$req ) {
                    $self->_die( "Failed to download file at URL 'http://" . $OPTS{'host'} . $file_url . "'." );
                }
                $basefile_hostaddr = $self->{'connectedHostAddress'};

                # Make a copy so we have an intact compressed version to place in the final location.

                my $copy = Cpanel::FileUtils::Copy::safecopy( $tmp_file_a, $tmp_file_b );

                if ( !$copy ) {
                    unlink $tmp_file_a;
                    $self->_die("Failed to make working copy of downloaded file.");
                }

                if ( $compressed_ext eq 'bz2' ) {
                    require Cpanel::Sync::Common;
                    Cpanel::Sync::Common::unbzip2($tmp_file_b);
                    $tmp_file_b =~ s/\.bz2$//;
                }
                elsif ( $compressed_ext eq 'xz' ) {
                    require Cpanel::SafeRun::Simple;
                    Cpanel::SafeRun::Simple::saferun( qw{ unxz -f }, $tmp_file_b )
                      and die "failed to extract '$tmp_file_b': $!";
                }

                ( $verification_data, $verification_message ) = $gpg->files(
                    files    => $tmp_file_b,
                    sig_data => $signature_data,
                    mirror   => $OPTS{'host'},
                    url      => $file_url
                );

                if ($verification_data) {
                    $self->{'logger'}->info($verification_message);
                    $self->{'sig_data'} = $verification_data;
                    unlink $destfile;
                    rename $tmp_file_a, $destfile;
                    unlink $tmp_file_b;
                    return wantarray ? ($req) : $req;
                }
                else {
                    unlink $tmp_file_a;
                    unlink $tmp_file_b;
                }
            }
            else {
                # Uncompressed 'destfile' case.
                # Also handles the case where HttpRequest will
                # uncompress
                my $tmp_file = $destfile . '_' . Cpanel::Rand::Get::getranddata(8);

                $OPTS{'url'}      = $file_url;
                $OPTS{'destfile'} = $tmp_file;

                # In the 'destfile' case, _request_file() returns only the '$complete' value.
                # So, this is a valid check of whether or not the download succeeded, even if content is 0 bytes.

                # Note: uncompress gets transparently handled by
                # _request_file()

                my $req = $self->_request_file(%OPTS);

                if ( !$req ) {
                    $self->_die( "Failed to download file at URL 'http://" . $OPTS{'host'} . $file_url . "'." );
                }
                $basefile_hostaddr = $self->{'connectedHostAddress'};

                ( $verification_data, $verification_message ) = $gpg->files(
                    files    => $tmp_file,
                    sig_data => $signature_data,
                    mirror   => $OPTS{'host'},
                    url      => $file_url
                );

                if ($verification_data) {
                    $self->{'logger'}->info($verification_message);
                    $self->{'sig_data'} = $verification_data;
                    unlink $destfile;
                    rename $tmp_file, $destfile;
                    return wantarray ? ($req) : $req;
                }
                else {
                    unlink $tmp_file;
                }
            }
        }
        else {

            # Direct file data return case.

            $OPTS{'url'} = $file_url;

            # In the direct-return case, _request_file() can return an array containing the downloaded data and "$complete".
            # We can check the "$complete" value to check download success, even if content is 0 bytes.

            my ( $file_data, $complete ) = $self->_request_file(%OPTS);

            if ( !$complete ) {
                $self->_die( "Failed to download URL 'http://" . $OPTS{'host'} . $file_url . "'." );
            }
            $basefile_hostaddr = $self->{'connectedHostAddress'};

            ( $verification_data, $verification_message ) = $gpg->files(
                files_data => $file_data,
                sig_data   => $signature_data,
                mirror     => $OPTS{'host'},
                url        => $file_url
            );

            if ($verification_data) {
                $self->{'logger'}->info($verification_message);
                $self->{'sig_data'} = $verification_data;
                return wantarray ? ( $file_data, $complete ) : $file_data;
            }
        }

        # Failed a single verification pass
        $self->_output("Signature verification failed using file from IP ${basefile_hostaddr} and signature from IP ${signature_hostaddr}");
        if ( $basefile_hostaddr eq $signature_hostaddr ) {
            $self->_skip_failed_mirror();
            $self->disconnect();
        }
        else {
            $self->_output("...retrying ${basefile_hostaddr}...");
        }
        $self->_output("\n");

        # repeat
    }

    # Failed all verification passes
    $self->_sigerror_die( "Signature verification failed for URL 'http://" . $OPTS{'host'} . $file_url . "'. ${verification_message}" );

    return 1;
}

sub _fetcher {
    my ( $self, $timeout, %params ) = @_;
    my $fetcher = $self->{fetcher};
    return Cpanel::HTTP::Tiny::FastSSLVerify->new( timeout => $timeout, %params ) if !$fetcher || $fetcher->{timeout} != $timeout;
    return $fetcher;
}

sub _request_file {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my ( $self, %OPTS ) = @_;

    my $host             = $OPTS{'host'};
    my $url              = $OPTS{'url'};
    my $destfile         = $OPTS{'destfile'}         || '';
    my $http_retry_count = $OPTS{'http_retry_count'} || $self->{'http_retry_count'};
    my $uncompress       = ( defined $OPTS{'uncompress'} && length $OPTS{'uncompress'} && $OPTS{'uncompress'} && $OPTS{'url'} =~ m/\.(bz2|xz)$/ );
    my $uncompress_ext   = $uncompress ? $1 : undef;

    my $compress_raw_bzip2_obj;
    my $compress_raw_lzma_obj;

    my $fetcher = $self->{fetcher} = $self->_fetcher( $self->{'timeout'} );

    if ($uncompress) {
        require Cpanel::Sync::Common;
        if ( !$Cpanel::Sync::Common::hasbzip2 && $uncompress_ext eq 'bz2' ) {
            $destfile .= '.bz2';
        }
    }
    my $complete = 0;
    my $page     = '';
    my $quiet    = $self->{'hideOutput'} || 0;
    $url =~ tr/\///s;    # squash duplicate "/"

    ( $host, $OPTS{'port'} ) = split /:/, $host, 2 if !defined $OPTS{'port'} && $host =~ tr/://;

    # sanity check, otherwise this causes an indefinite hang (or at least till the remote side hangs up, if we even get that far) #

    die '[ARGUMENT] a host must be specified at ' . (caller)[0] . ' line ' . (caller)[2] . "\n"
      if !$host;
    die '[ARGUMENT] a URL must be specified at ' . (caller)[0] . ' line ' . (caller)[2] . "\n"
      if !$url;

    print STDERR "[request] $host/$url\n" if $DEBUG;

    $url = "/$url" unless $url =~ m{^/};

    my $full_url = "http://$host" . ( $OPTS{'port'} ? ":$OPTS{'port'}" : "" ) . "$url";

    $self->_output( ( "\t" x $self->{'level'}++ ) . "Fetching $full_url (connected:" . $self->{'connected'} . ')....' );

    my $fh;
    my $addresses = $OPTS{'addresslist'};

    {
        my $httptrycount = 0;

      HTTP_TRY:
        while ( !$complete && $httptrycount < $http_retry_count ) {    # should be < then because we increment in the loop
            ++$httptrycount;
            if ($uncompress) {
                require Cpanel::Sync::Common;
                if ( $Cpanel::Sync::Common::hasbzip2 && $uncompress_ext eq 'bz2' ) {
                    ($compress_raw_bzip2_obj) = Compress::Raw::Bunzip2->new( $Cpanel::Sync::Common::BZIP2_OVERWRITE_OUTPUT, $Cpanel::Sync::Common::BZIP2_CONSUME_INPUT );
                }
                elsif ( $Cpanel::Sync::Common::haslzma && $uncompress_ext eq 'xz' ) {
                    ($compress_raw_lzma_obj) = Compress::Raw::Lzma::StreamDecoder->new();
                }
            }

            $self->_output("...(request attempt $httptrycount/$http_retry_count)...");

            my $method = $OPTS{'method'} || 'GET';
            my %reqargs;
            $reqargs{'headers'} = _convert_headers( $OPTS{'headers'} || {} );
            $reqargs{'content'} = $OPTS{'body'} if $OPTS{'body'};

            if ( length $destfile ) {
                my $callback;
                open( $fh, '>', $destfile ) or die "Can't open file: $!";
                if ($compress_raw_bzip2_obj) {
                    $callback = sub {
                        my $status = $compress_raw_bzip2_obj->bzinflate( $_[0], my $output );
                        if ( $status != $Cpanel::Sync::Common::BZ_OK && $status != $Cpanel::Sync::Common::BZ_STREAM_END || !defined($output) ) {
                            die "Decompressing chunked bzip2 data from $url to $destfile failed: $status";
                        }
                        print {$fh} $output;
                    };
                }
                elsif ($compress_raw_lzma_obj) {
                    $callback = sub {
                        my $status = $compress_raw_lzma_obj->code( $_[0], my $output );
                        if ( $status != $Cpanel::Sync::Common::LZMA_OK && $status != $Cpanel::Sync::Common::LZMA_STREAM_END || !defined($output) ) {
                            die "Decompressing chunked lzma data from $url to $destfile failed: $status";
                        }
                        print {$fh} $output;
                    };
                }
                else {
                    $callback = sub {
                        print {$fh} $_[0];
                    };
                }
                $reqargs{'data_callback'} = $callback;
            }
            else {
                $reqargs{'data_callback'} = sub {
                    $page .= $_[0];
                };
            }

            my $actual_url = $self->_initrequest(
                host         => $host,
                url          => $url,
                port         => $OPTS{'port'},
                headers      => $reqargs{'headers'},
                addresslist  => $OPTS{'addresslist'},
                attempt      => $httptrycount,
                max_attempts => $http_retry_count,
                destfile     => $destfile,
            ) or next HTTP_TRY;

            # NOTE: This will only work with our patched version of HTTP::Tiny.
            # Other systems will fall back to normal DNS resolution for the
            # mirror, which is okay for perlinstaller and such, since we're not
            # talking to the mirrors.
            $reqargs{'peer'} = $self->{'connectedHostAddress'};

            $self->_output('...receiving...');
            my $response = eval { $fetcher->request( $method, $actual_url, \%reqargs ); };
            $response = { status => 599 } if $@;

            if ( $self->{die_on_4xx_5xx} && $response && $response->{status} =~ /^[45]/ ) {
                require Cpanel::Exception;
                die Cpanel::Exception::create(
                    'HTTP::Server',
                    [
                        method  => $method,
                        url     => $actual_url,
                        status  => $response->{status},
                        reason  => $response->{reason},
                        headers => $response->{headers},
                        content => $response->{content},
                    ]
                );
            }

            $complete = ( $response->{status} =~ /^2\d\d$/ ? 1 : 0 );
            my $status   = $self->{last_status} = $response->{status};
            my $httpline = "$status $response->{reason}";

            if ( $response->{status} == 599 ) {
                my $error = $response->{content};
                chomp $error;
                $self->_output("...$error...");
                $self->{'connected'} = 0;
                $self->_skip_failed_mirror();
                next HTTP_TRY;
            }

            if ( $status !~ /^2/ ) {
                $self->_output("Error $status while fetching URL $full_url\n");
                if ( length $destfile ) {
                    close($fh);
                    unlink $destfile;
                }
                $self->{'last_exception'} = "$status - $httpline - HTTP ERROR";
            }

            if ($complete) {
                $self->{'connectedHostFailCount'}{ $self->{'connectedHostAddress'} } = 0;
            }
            else {
                $self->disconnect();
                if ( ++$self->{'connectedHostFailCount'}{ $self->{'connectedHostAddress'} } < 3 ) {
                    $self->_output("...server closed connection (failcount=$self->{'connectedHostFailCount'}{$self->{'connectedHostAddress'}})...");
                    if ( $self->{'last_exception'} && $self->{'last_exception'} =~ m{HTTP ERROR} ) {

                        #
                        #  This mirror may be ok, however we will skip it for now and come back
                        #
                        $self->_skip_failed_mirror();
                    }
                }
                else {
                    $self->_output("...failover...");
                    $self->_remove_failed_mirror();
                }

                if ( $self->{'last_status'} eq '404' && grep { $_->{'die_on_404'} } $self, \%OPTS ) {
                    local $@ = $self->{'last_exception'};
                    die;
                }
                elsif ( $self->{'last_status'} eq '404' && grep { $_->{'return_on_404'} } $self, \%OPTS ) {
                    $self->{'level'}--;
                    return wantarray ? ( '', 0 ) : 0;
                }
                elsif ( $self->{'last_status'} eq '404' && grep { $_->{'exitOn404'} } $self, \%OPTS ) {
                    $self->_output("...Distribution not required.\n");
                    exit;
                }
            }

        }
    }

    if ( !$complete && grep { $_->{'die_on_error'} } $self, \%OPTS ) {
        local $@ = $self->{'last_exception'};
        die;
    }

    $self->_output("...request success...") if $complete;
    $self->_output("...Done\n");

    if ( length $destfile ) {
        close($fh);
        if ( !$uncompress ) {
        }
        elsif ( !$Cpanel::Sync::Common::hasbzip2 && $uncompress_ext eq 'bz2' ) {
            Cpanel::Sync::Common::unbzip2($destfile);
        }
        elsif ( !$Cpanel::Sync::Common::haslzma && $uncompress_ext eq 'xz' ) {
            my $suffix = "__DEFLATE__$$";
            rename $destfile, "$destfile.$suffix.xz"
              or die "Failed to rename temporary file '$destfile' to '$destfile.$suffix.xz': $!";
            require Cpanel::SafeRun::Simple;
            Cpanel::SafeRun::Simple::saferun( 'unxz', '-f', "$destfile.$suffix.xz" )
              and die "Failed to decompress XZ data from '$destfile'";
            rename "$destfile.$suffix", $destfile
              or die "Failed to rename decompressed temporary file '$destfile.$suffix' to '$destfile': $!";
        }
    }

    if ( $complete == 0 ) {
        $self->disconnect();
        $self->{'fetcher'} = $fetcher = undef;
    }
    else {
        $self->{'connected'} = 1;
    }

    $self->{'level'}--;
    if ( length $destfile ) {
        return wantarray ? ($complete) : $complete;
    }
    return wantarray ? ( $page, $complete ) : $page;
}

sub disconnect {
    my ($self) = @_;
    $self->_socket_destroy();
    return $self->{'connected'} = 0;
}

sub make_http_query_string {
    my ($query) = @_;
    return $query unless ref $query;    # If query is a string, return it.

    require Cpanel::Encoder::URI;
    my ( $querystr, $delim, $enckey ) = ( '', '' );
    if ( ref $query eq 'ARRAY' ) {
        if ( @{$query} & 1 ) {
            Cpanel::Debug::log_invalid('Query key with no value.');
            return;
        }
        my $val;

        # Using a C-style loop to walk the list without changing it.
        for ( my $i = 0; $i < $#{$query}; $i += 2 ) {
            ( $enckey, $val ) = ( Cpanel::Encoder::URI::uri_encode_str( $query->[$i] ), $query->[ $i + 1 ] );
            next unless $enckey;    #if we don't have a key, ignore it

            if ( ref $val eq 'ARRAY' ) {

                # Convert an array of values into individual fields.
                $querystr .= $delim . join( '&', map { "$enckey=" . ( Cpanel::Encoder::URI::uri_encode_str($_) // '' ) } @{$val} );
            }
            else {
                $querystr .= "$delim$enckey=" . ( Cpanel::Encoder::URI::uri_encode_str($val) // '' );
            }
            $delim ||= '&';
        }
    }
    elsif ( ref $query eq 'HASH' ) {
        foreach my $key ( sort keys %{$query} ) {
            $enckey = Cpanel::Encoder::URI::uri_encode_str($key);
            next unless $enckey;    #if we don't have a key, ignore it

            if ( ref $query->{$key} eq 'ARRAY' ) {

                # Convert an array of values into individual fields.
                $querystr .= $delim . join( '&', map { "$enckey=" . ( Cpanel::Encoder::URI::uri_encode_str($_) // '' ) } @{ $query->{$key} } );
            }
            else {
                $querystr .= "$delim$enckey=" . ( Cpanel::Encoder::URI::uri_encode_str( $query->{$key} ) // '' );
            }
            $delim ||= '&';
        }
    }
    else {
        Cpanel::Debug::log_invalid('Unrecognized type for query parameter.');
        return;
    }

    return $querystr;
}

# Old 'post' interface, only handles simple responses
# Use httppost (below) in new code.
sub http_post_req {
    my ( $self, $args_hr ) = @_;

    require Cpanel::Encoder::URI;
    my $query = $args_hr->{'query'};
    if ( ref $args_hr->{'query'} eq 'HASH' ) {
        $query = '';
        foreach my $key ( keys %{ $args_hr->{'query'} } ) {
            if ( ref $args_hr->{'query'}{$key} eq 'ARRAY' ) {
                for my $val ( @{ $args_hr->{'query'}{$key} } ) {
                    $query .=
                      $query
                      ? "&$key=" . Cpanel::Encoder::URI::uri_encode_str($val)
                      : "$key=" . Cpanel::Encoder::URI::uri_encode_str($val);
                }
            }
            else {
                $query .=
                  $query
                  ? "&$key=" . Cpanel::Encoder::URI::uri_encode_str( $args_hr->{'query'}{$key} )
                  : "$key=" . Cpanel::Encoder::URI::uri_encode_str( $args_hr->{'query'}{$key} );
            }
        }
    }

    my $postdata_len = length($query);

    my $proto = getprotobyname('tcp');
    return unless defined $proto;

    socket( my $socket_fh, &Socket::AF_INET, &Socket::SOCK_STREAM, $proto );
    return unless $socket_fh;

    my $iaddr = gethostbyname( $args_hr->{'host'} );
    my $port  = $self->_socket_default_port();
    return unless ( defined $iaddr && defined $port );

    my $sin = Socket::sockaddr_in( $port, $iaddr );
    return unless defined $sin;

    if ( connect( $socket_fh, $sin ) ) {

        send $socket_fh, "POST /$args_hr->{'uri'} HTTP/1.0\r\nContent-Length: $postdata_len\r\nHost: $args_hr->{'host'}\r\n\r\n$query", 0;

        if ( ref $args_hr->{'output_handler'} eq 'CODE' ) {
            my $in_header = 1;
            while (<$socket_fh>) {
                if ( /^\n$/ || /^\r\n$/ || /^$/ ) {
                    $in_header = 0;
                    next;
                }

                $args_hr->{'output_handler'}->( $_, $in_header );
            }
        }
    }

    close $socket_fh;
    return;
}

sub download {
    my ( $self, $url, $file, $is_signed ) = @_;

    unlink $file if defined $file;
    $is_signed = defined $is_signed ? $is_signed : $self->{'signed'};

    my $parsed_url = Cpanel::URL::parse($url);
    my $res        = $self->request(
        'host'     => $parsed_url->{'host'},
        'url'      => $parsed_url->{'uri'},
        'destfile' => $file,
        'protocol' => 0,
        'method'   => 'GET',
        'signed'   => $is_signed,
    );
    return $res;
}

# handles uploading of content body on request #
sub http_request {
    my ( $self, $p_method, $p_host, $p_uri, %p_options ) = @_;

    # sanity #

    die '[ARGUMENT] a host must be specified at ' . (caller)[0] . ' line ' . (caller)[2] . "\n"
      if !$p_host;
    die '[ARGUMENT] a URI must be specified at ' . (caller)[0] . ' line ' . (caller)[2] . "\n"
      if !$p_uri;

    # process input parameters #
    my $method = $p_options{'method'} || $p_method;
    die '[ARGUMENT] a method must be specified at ' . (caller)[0] . ' line ' . (caller)[2] . "\n"
      if !$p_method;

    my $content_type = $p_options{'content_type'};

    # if a savefile was requested, then unlink it if it exists now #
    unlink $p_options{'file'}
      if defined $p_options{'file'};

    # setup options hash first, we'll update later #
    my %OPTS = (
        'host'     => $p_host,
        'port'     => $p_options{'port'},
        'url'      => $p_uri,
        'protocol' => 0,
        'method'   => $method,
        'destfile' => $p_options{'file'}
    );

    # content body? #
    if ( defined $p_options{'content'} ) {
        $OPTS{'body'} = $p_options{'content'};
        $content_type ||= 'text/plain';
    }

    # handle headers #
    my %headers;
    %headers = %{ $p_options{'headers'} }
      if ref $p_options{'headers'} eq ref {};
    $headers{'Content-Type'} = $content_type
      if $content_type;
    $OPTS{'headers'} = join( '', map { "$_: $headers{$_}\r\n" } keys %headers )
      if keys %headers;

    return $self->request(%OPTS);
}

sub httpreq {
    my ( $self, $host, $url, $file, %p_options ) = @_;
    return $self->http_request( 'GET', $host, $url, 'file' => $file, %p_options );
}

# handles uploading of content body on request #
sub httpput {
    my ( $self, $host, $uri, $content, %p_options ) = @_;
    return $self->http_request( 'PUT', $host, $uri, 'content' => $content, %p_options );
}

# New 'post' interface. Works like httpreq except with a body.
sub httppost {
    my ( $self, $host, $url, $qparms, $file, %p_options ) = @_;
    my $content;
    $content = make_http_query_string($qparms)
      if defined $qparms;
    return $self->http_request( 'POST', $host, $url, 'content' => $content, 'content_type' => 'application/x-www-form-urlencoded', 'file' => $file, %p_options );
}

sub skiphost {
    my $self = shift;
    $self->disconnect();
    $self->_remove_failed_mirror();
    return;
}

sub _getAddressList {    ## no critic(Subroutines::ProhibitExcessComplexity)  -- Added with case SEC-398, out of scope for a TSR.
    my ( $self, $host, $port ) = @_;

    print STDERR "[_getAddressList][$host]\n" if $DEBUG;

    my $quiet                 = $self->{'hideOutput'} || 0;
    my $resolve_attempt_count = 1;

    my ( $cache_key, $homedir, @trueaddresses, $loaded_cache );

    if ( $self->{'use_dns_cache'} ) {
        $homedir   = ( getpwuid($>) )[7];
        $cache_key = $host;
        $cache_key =~ s/\///g;

        if ( !-e $homedir . '/.HttpRequest' ) {
            mkdir $homedir . '/.HttpRequest', 0700;
        }
        if ( -e $homedir . '/.HttpRequest/' . $cache_key && ( ( stat(_) )[9] + $self->{'dns_cache_ttl'} ) > time() ) {
            if ( open( my $address_cache_fh, '<', $homedir . '/.HttpRequest/' . $cache_key ) ) {
                local $/;
                @trueaddresses = split( /\n/, readline($address_cache_fh) );
                $loaded_cache  = 1;
                close($address_cache_fh);
                $self->_output("Using dns cache file $homedir/.HttpRequest/$cache_key...");
            }
            else {
                $self->_output("Loading dns cache file $homedir/.HttpRequest/$cache_key failed ($!)...");
            }
        }
    }

    while ( !@trueaddresses ) {
        $loaded_cache = 0;

        $self->_output("Resolving $host...(resolve attempt $resolve_attempt_count/${MAX_RESOLVE_ATTEMPT})...");
        @trueaddresses = Cpanel::SocketIP::_resolveIpAddress($host);
        last if (@trueaddresses);
        $self->_output("Resolving $host using backup method...");
        eval 'require Cpanel::DnsRoots; $has_cpanel_dnsRoots=1'                   if !$has_cpanel_dnsRoots;
        @trueaddresses = 'Cpanel::DnsRoots'->can('resolveIpAddressBAMP')->($host) if $has_cpanel_dnsRoots;
        last                                                                      if ( @trueaddresses || !$self->{'retry_dns'} || $resolve_attempt_count++ >= $MAX_RESOLVE_ATTEMPT );

        $self->_output("Waiting for dns resolution to become available....");
        sleep 1;
    }

    print STDERR "[finished address lookups]\n" if $DEBUG;

    #DEBUG TEST
    if ($SIMULATE_FAILURE) {
        @trueaddresses = ( '1.1.1.1', '2.2.2.2' );
    }

    #
    #
    #
    Cpanel::ArrayFunc::Shuffle::shuffle( \@trueaddresses );

    if ( !@trueaddresses ) {
        my $errormsg = "$host could not be resolved to an IP address. Please check your /etc/resolv.conf file.\n";
        Cpanel::Debug::log_warn($errormsg);
        if ( $self->{'die_on_error'} ) {
            die $errormsg;
        }
        return wantarray ? () : [];
    }
    elsif ( !$self->{'speed_test_enabled'} ) {
        @trueaddresses = ( $trueaddresses[0] );
    }
    #
    # If we have more than one address we will attempt to find out which one is
    # the fastest one so we can use the fastest host for downloads.
    #
    elsif ( @trueaddresses > 1 ) {
        #
        # resolveIpAddress fuctions may return data in predictable order.
        # at this point order does not matter.
        #
        print STDERR "[has resolved, testing]\n" if $DEBUG;
        if ( !$loaded_cache ) {

            if ( $self->{'use_mirror_addr_list'} || $host eq 'httpupdate.cpanel.net' ) {
                $self->_output("\n");
                my $mirror_addr_list = $self->request( 'level' => 1, 'addresslist' => \@trueaddresses, 'host' => $host, 'url' => '/mirror_addr_list', 'protocol' => 1, 'http_retry_count' => 3 );
                my @mirror_addr_list_ADDR_LIST;
                if ($mirror_addr_list) {
                    foreach my $line ( split( /\n/, $mirror_addr_list ) ) {
                        chomp($line);
                        my ($ipaddr) = split( /=/, $line );
                        push @mirror_addr_list_ADDR_LIST, $ipaddr if ( $ipaddr =~ /^[\d\.\:]+$/ );
                    }
                }
                if (@mirror_addr_list_ADDR_LIST) {
                    $self->_output( "...found " . scalar @mirror_addr_list_ADDR_LIST . " host(s) from mirror_addr_list..." );
                    @trueaddresses = @mirror_addr_list_ADDR_LIST;
                }
            }
            if ( $self->{'use_dns_cache'} && @trueaddresses ) {
                if ( open( my $address_cache_fh, '>', $homedir . '/.HttpRequest/' . $cache_key ) ) {
                    print {$address_cache_fh} join( "\n", @trueaddresses );
                    close($address_cache_fh);
                }
            }
        }
        #
        #  This will get incremented every time we do a mirror search.    This gets called from
        #  _getAddressList which is called from _initrequest which is called in the main request loop (label HTTP_TRY).
        #  If the main request loop (label HTTP_TRY) will end up getting here a forth time then we
        #  die because its very unlikely we will ever be able to retrieve anything since we have
        #  already went though the cache and a full lookup/search.
        #
        if ( ++$self->{'mirror_search_attempts'}{$host} == 4 ) {    # first time  = loaded from cache
                                                                    # second time = rebuild due to failed mirrors from cache
                                                                    # third time = rebuild due to failed mirrors
                                                                    # forth time  = already tried to rebuild, fail
            die "$host did not have any working mirrors.  Please check your internet connection or dns server.";
        }
        $self->_output( "...searching for mirrors (mirror search attempt " . $self->{'mirror_search_attempts'}{$host} . "/3)..." );

        #
        #  MirrorSearch will find the fatest urls and return a list.
        #  We will take the list replace our address list with it (in order of fastest first)
        #

        require Cpanel::MirrorSearch;
        my @goodurls = Cpanel::MirrorSearch::findfastest(
            'days'  => ( 2.0 / 24 ),
            'key'   => $host,
            'count' => 10,
            'urls'  => [ Cpanel::UrlTools::buildurlfromuri( \@trueaddresses, $self->{'speed_test_file'} ) ],
            'quiet' => $self->{'htmlOutput'} ? 1 : $quiet,
            'port'  => $port || $self->_socket_default_port()
        );

        if ( @trueaddresses = Cpanel::UrlTools::extracthosts( \@goodurls ) ) {
            $self->_output("...mirror search success...");

            #
            # Reset the mirror search attempts since we have had success
            #
            $self->{'mirror_search_attempts'}{$host} = 0;
        }
        else {
            $self->_output("...mirror search failed...");
        }

        #
        #  If we have failed to get any addresses we destroy the cache so that the next time
        #  we do not use it.
        #
        if ( !@trueaddresses && $self->{'use_dns_cache'} ) {

            # If we run out of hosts destroy the cache so we can get a new list
            $self->_destroy_ip_cache($host);
        }

    }

    #DEBUG TEST
    if ($SIMULATE_FAILURE) {
        return wantarray ? () : [];
    }

    return wantarray ? @trueaddresses : \@trueaddresses;
}

sub _remove_failed_mirror {
    my $self = shift;

    my $addr = $self->{'connectedHostAddress'};    #ip of connected host

    print STDERR "[_remove_failed_mirror] $addr\n" if $DEBUG;

    $self->_output("...removing $addr...");

    if ( $self->{'host'} ) {
        @{ $self->{'hostIps'}{ $self->{'host'} } } = grep( !m/^\Q$addr\E$/, @{ $self->{'hostIps'}{ $self->{'host'} } } );
    }
    require Cpanel::MirrorSearch;
    Cpanel::MirrorSearch::remove_mirror( 'key' => $self->{'connectedHostname'}, 'addr' => $addr );

    if ( !$self->{'host'} || !@{ $self->{'hostIps'}{ $self->{'host'} } } && $self->{'use_dns_cache'} ) {

        # If we run out of hosts destroy the cache so we can get a new list
        $self->_destroy_ip_cache();
    }

    # We used to move the failed mirror to the end of the list, but now we just remove it and force a rescan when we run out
    # push( @{ $self->{'hostIps'}{$self->{'host'}} }, $addr );
    #move the failed ip to the end of the list
    return;
}

# Skip failed hosts without affecting the DNS mirror cache (soft failures)
sub _skip_failed_mirror {
    my $self = shift;

    my $addr = $self->{'connectedHostAddress'};    #ip of connected host

    print STDERR "[_skip_failed_mirror] $addr\n" if $DEBUG;

    $self->_output("...skipping $addr...");

    @{ $self->{'hostIps'}{ $self->{'host'} } } = grep( !m/^\Q$addr\E$/, @{ $self->{'hostIps'}{ $self->{'host'} } } );

    push @{ $self->{'skipped_hostIps'}{ $self->{'host'} } }, $addr;    # if ! grep( !m/^\Q$addr\E$/, @{ $self->{'skipped_hostIps'}{ $self->{'host'} } } );;

    # If the list of hostIps is less than the try count, reset the list and try same hosts again to achieve the try count
    if ( !@{ $self->{'hostIps'}{ $self->{'host'} } } && @{ $self->{'skipped_hostIps'}{ $self->{'host'} } } ) {
        @{ $self->{'hostIps'}{ $self->{'host'} } } = @{ $self->{'skipped_hostIps'}{ $self->{'host'} } };
        $self->{'skipped_hostIps'}{ $self->{'host'} } = [];            # important to clear out this since we moved them to hostIps
    }
    return;
}

sub _destroy_ip_cache {
    my $self      = shift;
    my $cache_key = shift || $self->{'connectedHostname'};
    my $homedir   = ( getpwuid($>) )[7];
    $cache_key =~ s/\///g;
    unlink("$homedir/.HttpRequest/$cache_key");    # Kill the cache if we run out of working hosts so it will rebuild
    return;
}

# Taken from cPanel::PublicAPI.
sub _convert_headers {
    my ($headers) = @_;
    if ( !ref $headers ) {
        my @lines = split /\r\n/, $headers;
        $headers = {};
        foreach my $line (@lines) {
            last unless length $line;
            my ( $key, $value ) = split /:\s*/, $line, 2;
            next unless length $key;
            $headers->{$key} ||= [];
            push @{ $headers->{$key} }, $value;
        }
    }
    return $headers;
}

sub _socket_default_port {
    my $self = shift;
    return ( getservbyname( 'http', 'tcp' ) )[2];
}

sub _socket_destroy {
    my $self = shift;
    delete $self->{'fetcher'};
    return 1;
}

sub _initrequest {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my ( $self, %OPTS ) = @_;
    $self->{'last_status'} = undef;

    print STDERR "\n\n\n\n[_initrequest]\n" if $DEBUG;

    my $host = $OPTS{'host'};
    $self->{'host'} = $host || die "Host is missing";

    $self->{'hostIps'}{$host}         ||= [];
    $self->{'skipped_hostIps'}{$host} ||= [];

    my $url           = $OPTS{'url'};
    my $http_protocol = $OPTS{'http_protocol'};
    my $destfile      = $OPTS{'destfile'};
    my $headers       = $OPTS{'headers'};
    my $port          = $OPTS{'port'};
    my $method        = $OPTS{'method'} || 'GET';

    #
    # If we switch the host we are connecting to we need to unset the connected
    # flag so the connect is dropped (if open) and we connect to the new host
    #
    $self->{'connected'} = 0 if ( $self->{'connectedHostname'} ne $host );

    my $has_an_addresslist = ( exists $OPTS{'addresslist'} && ref $OPTS{'addresslist'} ) ? 1 : 0;

    #
    # If we have switched from using an addresslist to not using an addresslist
    # we need to clear out the hostIps and skipped_hostIps and using_addresslist.
    #
    if ( ( $self->{'using_addresslist'}{$host} && !$has_an_addresslist ) || ( !$self->{'using_addresslist'}{$host} && $has_an_addresslist ) || $SIMULATE_FAILURE ) {
        delete $self->{'using_addresslist'}{$host};
        $self->{'hostIps'}{$host} = $self->{'skipped_hostIps'}{$host} = [];
        $self->{'connected'}      = 0;                                        # We must also disconnect because we may not be connected
                                                                              # to the correct host since the addresses may have changed
    }

    if ($DEBUG) {
        print STDERR "[about to get ips has_an_addresslist=($has_an_addresslist)]\n";
        my $hostips_defined         = @{ $self->{'hostIps'}{$host} }         ? 1 : 0;
        my $skipped_hostips_defined = @{ $self->{'skipped_hostIps'}{$host} } ? 1 : 0;
        print "[HOSTIPS_DEFINED] $hostips_defined [SKIPPEDHOSTIPS_DEFINED] $skipped_hostips_defined\n";
    }

    #
    #  If we have not yet resolved the hostIps then we need to load up the hostIps array
    #
    if ( !@{ $self->{'hostIps'}{$host} } && !@{ $self->{'skipped_hostIps'}{$host} } ) {
        print STDERR "[...doing address lookup block...]\n" if $DEBUG;
        if ( @{ $self->{'hostIps'}{$host} } = $has_an_addresslist ? @{ $OPTS{'addresslist'} } : $self->_getAddressList( $host, $port ) ) {
            if ($has_an_addresslist) { $self->{'using_addresslist'}{$host} = 1; }
            if ($DEBUG) {
                my $hostips_defined = @{ $self->{'hostIps'}{$host} } ? 1 : 0;
                print STDERR "[....addresslist load or getAddressList ok...] ($hostips_defined)\n";
            }

            # ok to continue
        }
        else {
            print STDERR "[...failed to resolve $host...]\n" if $DEBUG;

            return;
        }

    }

    print STDERR "[init_req finished populating hostIps]\n" if $DEBUG;

    my $port_suffix = $OPTS{'port'} ? ":$OPTS{'port'}" : "";

    $url =~ s/\s/\%20/g;
    $url ||= '/';

    $headers->{Accept} ||= "text/html, text/plain, audio/mod, image/*, application/msword, application/pdf, application/postscript, text/sgml, */*;q=0.01";

    foreach my $addr ( @{ $self->{'hostIps'}{$host} } ) {
        $self->{'connectedHostAddress'} = $addr;    #must be set before we actually connect() in setupsocket
        $self->{'connectedHostname'}    = $host;
        $self->{'connectedHostFailCount'}{$addr} ||= 0;
        $self->{'connected'} = 1;
        my $local_logger = $self->{'logger'};

        # Log each time we notice HttpRequest is connected to a new host if
        # the user has asked us to.
        if ( $self->{'announce_mirror'} && ( !defined $self->{'_previous_mirror_used'} || $self->{'_previous_mirror_used'} ne $addr ) ) {
            $self->{'_previous_mirror_used'} = $addr;
            $local_logger->info("Using mirror '${addr}' for host '${host}'.");
        }
        last;
    }
    $self->_output( '@' . $self->{'connectedHostAddress'} . '...' );

    return "http://$host$port_suffix$url";
}

sub _die {
    my ( $self, $msg ) = @_;

    if ( $self->{'logger'}->can('die') ) {
        return $self->{'logger'}->die($msg);
    }
    else {
        die "$msg\n";
    }
}

sub _sigerror_die {
    my ( $self, $msg ) = @_;

    return $self->_die( $msg . ' Please see https://go.cpanel.net/sigerrors for further information about this error.' );
}

sub get_crypt_gpg_vendorkey_verify {
    my ( $self, %opts ) = @_;

    my ( $gpg_vendor, $gpg_category ) = @opts{qw(vendor categories)};
    $gpg_vendor   ||= $self->{'vendor'};
    $gpg_category ||= $self->{'categories'};
    my $key = join( '__', $gpg_vendor, ref $gpg_category ? @$gpg_category : $gpg_category );

    return $self->{'_gpg_verify'}{$key} if $self->{'_gpg_verify'}{$key};

    require Cpanel::Crypt::GPG::VendorKeys::Verify;

    my ( $gpg, $gpg_msg ) = Cpanel::Crypt::GPG::VendorKeys::Verify->new(
        vendor     => $gpg_vendor,
        categories => $gpg_category,
    );

    return ( $gpg, $gpg_msg ) if !$gpg;

    $self->{'_gpg_verify'}{$key} = $gpg;
    return ( $gpg, $gpg_msg );
}

1;
