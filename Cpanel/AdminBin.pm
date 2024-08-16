package Cpanel::AdminBin;

# cpanel - Cpanel/AdminBin.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;
use Cpanel::Exception            ();
use Cpanel::FileUtils::Open      ();
use Cpanel::LoadFile             ();
use Cpanel::PwCache              ();
use Cpanel::Debug                ();
use Cpanel::Wrap                 ();
use Cpanel::Wrap::Config         ();
use Cpanel::AdminBin::Cache      ();
use Cpanel::AdminBin::Serializer ();

our $VERSION     = 2.2;
our $safecaching = 0;

#Use for:
#   SENDING a data structure
#   RECEIVING a text blob
#
# Always sets $Cpanel::CPERROR{$Cpanel::context} on error and does not return status of call
sub adminstor {
    my ( $bin, $key, $ref ) = @_;

    my $result = Cpanel::Wrap::send_cpwrapd_request(
        'namespace' => 'Cpanel',
        'module'    => $bin,
        'function'  => $key,
        'data'      => $ref,
        'action'    => 'run',
        'env'       => Cpanel::Wrap::Config::safe_hashref_of_allowed_env(),
    );

    return $result->{'data'};
}

#Use for:
#   SENDING a list of arguments - NONE of which may contain whitespace
#   RECEIVING a text blob
#
# Always sets $Cpanel::CPERROR{$Cpanel::context} on error and does not return status of call
sub adminrun {
    my ( $bin, @AG ) = @_;

    _trimws_safe( \@AG );

    my $function = shift @AG;

    my $full_arg = join( ' ', @AG );

    my $result = Cpanel::Wrap::send_cpwrapd_request(
        'namespace' => 'Cpanel',
        'module'    => $bin,
        'function'  => $function,
        'data'      => $full_arg,
        'action'    => 'run',
        'env'       => Cpanel::Wrap::Config::safe_hashref_of_allowed_env(),
    );

    return $result->{'data'};
}

#Use for:
#   SENDING a list of arguments
#   RECEIVING a data structure with call status and text blob
#
# Does not set $Cpanel::CPERROR on error. NOTE: the called admin script may still set $Cpanel::CPERROR.
sub run_adminbin_with_status {
    my ( $bin, @AG ) = @_;

    _trimws_safe( \@AG );

    my $function = shift @AG;

    my $full_arg = join( ' ', @AG );

    my $result = Cpanel::Wrap::send_cpwrapd_request_no_cperror(
        'namespace' => 'Cpanel',
        'module'    => $bin,
        'function'  => $function,
        'data'      => $full_arg,
        'action'    => 'run',
        'env'       => Cpanel::Wrap::Config::safe_hashref_of_allowed_env(),
    );

    return {
        'status'    => $result->{'error'} ? 0 : 1,
        'statusmsg' => $result->{'statusmsg'},
        'data'      => $result->{'error'} ? undef                                       : $result->{'data'},
        'error'     => $result->{'error'} ? _convert_data_to_error( $result->{'data'} ) : undef,
    };
}

#Use for:
#   SENDING a list of arguments
#   RECEIVING a data structure
#
# Always sets $Cpanel::CPERROR on error and does not return status of call
sub adminfetch {
    my ( $bin, $cachecfiles, $func, $result, @AG ) = @_;

    return _adminfetch(
        'module'            => ( $bin         || '' ),
        'function'          => ( $func        || '' ),
        'format'            => ( $result      || '' ),
        'cache_check_files' => ( $cachecfiles || '' ),
        'cache'             => 1,
        'args'              => \@AG,
    );
}

#Use for:
#   SENDING a list of arguments
#   RECEIVING a data structure
#
# Cachefile is given as an argument so that if a cachefile exists
# then it will be removed (also keeps the call the same as adminfetch)
#
# Always sets $Cpanel::CPERROR on error and does not return status of call
sub adminfetchnocache {
    my ( $bin, $cachecfiles, $func, $result, @AG ) = @_;

    return _adminfetch(
        'module'            => ( $bin         || '' ),
        'function'          => ( $func        || '' ),
        'format'            => ( $result      || '' ),
        'cache_check_files' => ( $cachecfiles || '' ),
        'cache'             => 0,
        'args'              => \@AG,
    );
}

#Use for:
#   SENDING a list of arguments
#   RECEIVING a data structure including call status
#
# Does not set $Cpanel::CPERROR on error and returns the status of the call
sub fetch_adminbin_with_status {
    my ( $bin, $cachecfile, $func, $result, @AG ) = @_;

    my $ret_val = _adminfetch(
        'module'            => ( $bin        || '' ),
        'function'          => ( $func       || '' ),
        'format'            => ( $result     || '' ),
        'cache_check_files' => ( $cachecfile || '' ),
        'cache'             => 1,
        'args'              => \@AG,
        'return_status'     => 1,
    );

    return {
        'status'    => $ret_val->{'error'} ? 0 : 1,
        'statusmsg' => $ret_val->{'statusmsg'},
        'data'      => $ret_val->{'error'} ? undef                                        : $ret_val->{'data'},
        'error'     => $ret_val->{'error'} ? _convert_data_to_error( $ret_val->{'data'} ) : undef,
    };
}

#Use for:
#   SENDING a list of arguments
#   RECEIVING a data structure including call status
#
# Cachefile is given as an argument so that if a cachefile exists
# then it will be removed (also keeps the call the same as adminfetch)
#
# Does not set $Cpanel::CPERROR on error and returns the status of the call
sub fetch_adminbin_nocache_with_status {
    my ( $bin, $cachecfile, $func, $result, @AG ) = @_;

    my $ret_val = _adminfetch(
        'module'            => ( $bin        || '' ),
        'function'          => ( $func       || '' ),
        'format'            => ( $result     || '' ),
        'cache_check_files' => ( $cachecfile || '' ),
        'cache'             => 0,
        'args'              => \@AG,
        'return_status'     => 1,
    );

    return {
        'status'    => $ret_val->{'error'} ? 0 : 1,
        'statusmsg' => $ret_val->{'statusmsg'},
        'data'      => $ret_val->{'error'} ? undef                                        : $ret_val->{'data'},
        'error'     => $ret_val->{'error'} ? _convert_data_to_error( $ret_val->{'data'} ) : undef,
    };
}

# This function is temporary, we will be doing a cleanup of the adminbin calls and will rework how errors are returned.
sub _convert_data_to_error {
    my ($data) = @_;

    return $data if !$data;

    $data =~ s/\A.\n//m;    # If this is an error, it shouldn't have the .\n format for data.

    return $data;
}

sub _process_response_data {
    my ( $response, $usecache, $return_status, $bin, $call_cachefile ) = @_;
    my $exitcode = $response->{'exit_code'};
    my $readok   = $response->{'status'};

    if ( !ref $response->{'data'} ) {
        my $res = $response->{'data'};

        if ( defined $exitcode && $exitcode == 0 && $readok ) {

            # Only save the cache if the exit code is good
            if ( defined $res && $usecache && Cpanel::FileUtils::Open::sysopen_with_real_perms( my $data_fh, $call_cachefile, 'O_WRONLY|O_TRUNC|O_CREAT', 0600 ) ) {
                print {$data_fh} $res;
                close($data_fh);
            }
        }

        return $response if $return_status;

        return $res || '';
    }
    else {
        my $res    = $response->{'data'};
        my $readok = $response->{'status'};
        if ( $exitcode == 0 && $readok ) {
            if ($usecache) {

                # file locking is not needed here since we do not use file locking to retrieve the data
                if ( Cpanel::FileUtils::Open::sysopen_with_real_perms( my $data_store_fh, $call_cachefile, 'O_WRONLY|O_TRUNC|O_CREAT', 0600 ) ) {
                    print {$data_store_fh} ${ $response->{'response_ref'} } or Cpanel::Debug::log_info("Write to $call_cachefile failed: $!");
                    close($data_store_fh)                                   or Cpanel::Debug::log_info("close($call_cachefile) failed: $!");
                }
                else {
                    Cpanel::Debug::log_warn("Could not write to $call_cachefile");
                }
            }
        }

        return $response if $return_status;
        return $res      if $readok;

        Cpanel::Debug::log_warn("Failed to retrieve storable data from $bin: $@");
        return {};
    }
}

sub _adminfetch {
    my %OPTS = @_;

    my $bin               = $OPTS{'module'};
    my $func              = $OPTS{'function'};
    my $cache_check_files = $OPTS{'cache_check_files'};
    my $result_format     = $OPTS{'format'};
    my $return_status     = $OPTS{'return_status'} ? 1 : 0;
    my @AG                = @{ $OPTS{'args'} };

    my $file = join( '_', $bin, $func, $AG[0] || () );

    my $res;
    my $homedir = $Cpanel::homedir || Cpanel::PwCache::gethomedir($>);

    my $call_cachefile = $homedir . '/.cpanel/datastore/' . $file;

    my $usecache = $OPTS{'cache'} && ( $Cpanel::AdminBin::safecaching ? 0 : 1 );

    if ( @AG && ref $AG[0] ) {
        $usecache = 0;    # cannot cache complex fetches
    }

    if ($usecache) {
        $res = _fetch_from_cache( $homedir, $cache_check_files, $file, $result_format );
        if ( defined $res ) {
            return ( ref $res ? $res->{'data'} : $res ) if !$return_status;
            return {
                'status'    => 1,
                'statusmsg' => 'Data retrieved from cache.',
                'data'      => $res->{'data'},
                'error'     => 0
            };
        }
    }

    my $data;
    if ( @AG && ref $AG[0] ) {
        $data = $AG[0];
    }
    else {
        $data = join( ' ', map { defined $_ ? $_ : '' } @AG );
    }

    my $wrap_call_coderef = $return_status ? \&Cpanel::Wrap::send_cpwrapd_request_no_cperror : \&Cpanel::Wrap::send_cpwrapd_request;
    my $response          = $wrap_call_coderef->(
        'namespace' => 'Cpanel',
        'module'    => $bin,
        'function'  => $func,
        'data'      => $data,
        'action'    => ( $result_format eq 'scalar' ? 'run' : 'fetch' ),
        'env'       => Cpanel::Wrap::Config::safe_hashref_of_allowed_env(),
    );
    return _process_response_data( $response, $usecache, $return_status, $bin, $call_cachefile );
}

sub _fetch_from_cache {
    my ( $homedir, $cache_check_files, $file, $result_format ) = @_;

    my $call_cachefile = $homedir . '/.cpanel/datastore/' . $file;
    my ( $mtimetobeat, $res );
    $mtimetobeat = 0;
    if ( ref $cache_check_files eq 'ARRAY' ) {
        foreach my $checkfile ( @{$cache_check_files} ) {
            my $cmtime = ( stat($checkfile) )[9] || 0;
            if ( $cmtime > $mtimetobeat ) {
                $mtimetobeat = $cmtime;
            }
        }
    }
    else {
        $mtimetobeat = ( stat($cache_check_files) )[9] || 0;
    }

    if ( Cpanel::AdminBin::Cache::check_cache_item( $mtimetobeat, $file ) ) {
        if ( $result_format eq 'scalar' ) {
            return Cpanel::LoadFile::loadfile($call_cachefile);
        }
        elsif ( -r $call_cachefile ) {
            if ( open( my $datastore_fh, '<', $call_cachefile ) ) {

                local $SIG{__DIE__} = 'DEFAULT';
                local $@;

                # Its perfectly ok not to be able to retrieve the cache
                # since we will just call the adminbinary (its slower of course)
                eval { $res = Cpanel::AdminBin::Serializer::LoadFile($datastore_fh) };

                close($datastore_fh) or warn "close($datastore_fh) failed: $!";
            }
        }
    }

    return $res;
}

sub _trimws_safe {
    my $arrayref = shift;
    for ( 0 .. $#$arrayref ) {
        if ( defined $arrayref->[$_] ) {

            #Don't bug out on whitespace at the ends; just trim it.
            if ( $arrayref->[$_] =~ tr/\r\n \t// ) {
                $arrayref->[$_] =~ s<^[\r\n \t]+><>;
                $arrayref->[$_] =~ s<[\r\n \t]+$><>;
            }

            #Spaces in the middle are bound to be wrong, so die().
            if ( $arrayref->[$_] =~ tr/\r\n \t// ) {
                die Cpanel::Exception::create( 'InvalidParameter', 'The parameter “[_1]” contains whitespace. This function cannot accept whitespace.', [ $arrayref->[$_] ] );
            }
        }
        else {
            $arrayref->[$_] = '';
        }
    }
    return;
}
1;
