package Cpanel::CachedCommand;

# cpanel - Cpanel/CachedCommand.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;
use Cpanel::StatCache            ();
use Cpanel::LoadFile             ();
use Cpanel::CachedCommand::Utils ();
use Cpanel::CachedCommand::Valid ();
use Cpanel::Debug                ();

our $VERSION = '2.8';

my %MEMORY_CACHE;

sub _is_memory_cache_valid {
    my %OPTS           = @_;
    my $datastore_file = $OPTS{'datastore_file'};

    if ( !exists $MEMORY_CACHE{$datastore_file} ) {
        print STDERR "_is_memory_cache_valid: rejecting $datastore_file because it does not exist in memory.\n" if $Cpanel::Debug::level;
        return 0;
    }

    my $ttl   = $OPTS{'ttl'};
    my $mtime = $OPTS{'mtime'};

    if ( !$ttl && $mtime && $MEMORY_CACHE{$datastore_file}->{'mtime'} == $mtime ) {
        print STDERR "_is_memory_cache_valid: accepting $datastore_file because it passes the mtime test.\n" if $Cpanel::Debug::level;
        return 1;
    }
    else {
        my $now = time();
        if ( $ttl && $MEMORY_CACHE{$datastore_file}->{'mtime'} > ( $now - $ttl ) ) {
            print STDERR "_is_memory_cache_valid: accepting $datastore_file because it passes the ttl test.\n" if $Cpanel::Debug::level;
            return 1;
        }
    }

    print STDERR "_is_memory_cache_valid: rejecting $datastore_file because it not pass the ttl or mtime test.\n" if $Cpanel::Debug::level;
    delete $MEMORY_CACHE{$datastore_file};
    return 0;
}

#NB: This looks at $> to determine absolute path. That may complicate
#testing, which generally runs as root.
sub invalidate_cache {
    my $ds_file = Cpanel::CachedCommand::Utils::invalidate_cache(@_);
    delete $MEMORY_CACHE{$ds_file};

    return;
}

sub _cached_cmd {
    my %OPTS = @_;

    my ( $binary, $ttl, $mtime, $exact, $regexcheck, $args_hr, $min_expire_time, $get_result_cr ) = (
        ( $OPTS{'binary'}          || '' ),
        ( $OPTS{'ttl'}             || 0 ),
        ( $OPTS{'mtime'}           || 0 ),
        ( $OPTS{'exact'}           || 0 ),
        ( $OPTS{'regexcheck'}      || '' ),
        ( $OPTS{'args_hr'}         || {} ),
        ( $OPTS{'min_expire_time'} || 0 ),
        ( $OPTS{'get_result_cr'}   || \&_default_get_result_cr ),
    );

    my @AG;
    if ( ref $OPTS{'args'} eq 'ARRAY' ) {
        @AG = @{ $OPTS{'args'} };
    }

    if ( substr( $binary, 0, 1 ) eq '/' && !-x $binary ) {
        return "$binary is missing or not executable";
    }
    my @SAFEAG = @AG;
    if ( !$exact && scalar @SAFEAG > 4 ) {

        # We used to cut this off at 3 arguments because we want to limit the length
        # of the filenames for the cache files so they do not get larger than the file
        # system permits.  The downside is we end up with a collision of names
        # so that
        #
        # rpm -q --queryformat %{VERSION} roundcube
        # and
        # rpm -q --queryformat %{VERSION} sl
        #
        # Would end up returning the same cache if we only allow 3 args.
        # Roundcube rpm query needs 4 args and its currently the longest arg
        # list we cache.  Ideally we would die here if the caller
        # sends more than 4 args since we cannot offer that level
        # of granularity
        #
        splice( @SAFEAG, 4 );
    }

    my $datastore_file = Cpanel::CachedCommand::Utils::_get_datastore_filename( $binary, @SAFEAG );

    if (
        _is_memory_cache_valid(
            'binary'         => $binary,
            'datastore_file' => $datastore_file,
            'ttl'            => $ttl,
            'mtime'          => $mtime
        )
    ) {
        return $MEMORY_CACHE{$datastore_file}->{'contents'};
    }

    my ( $datastore_file_size, $datastore_file_mtime ) = ( stat($datastore_file) )[ 7, 9 ];
    my $data_mtime;

    my ( $used_cache, $res );
    if (
        Cpanel::CachedCommand::Valid::is_cache_valid(
            'binary'               => $binary,
            'datastore_file'       => $datastore_file,
            'datastore_file_mtime' => $datastore_file_mtime,
            'ttl'                  => $ttl,
            'mtime'                => $mtime,
            'min_expire_time'      => $min_expire_time,
        )
    ) {
        $res        = Cpanel::LoadFile::loadfile_r( $datastore_file, { 'skip_exists_check' => 1 } );
        $data_mtime = $datastore_file_mtime;
        if ( $res && ( !$regexcheck || $$res =~ m/$regexcheck/ ) ) {
            $used_cache = 1;
        }
    }

    if ( !$used_cache ) {
        $data_mtime = _time();

        $res = $get_result_cr->( { binary => $binary, args => \@AG } );

        if ( !$regexcheck || ( defined $res && ( ref $res ? $$res : $res ) =~ m/$regexcheck/ ) ) {
            print STDERR "_cached_command: writing datastore file: $datastore_file " . ( $regexcheck ? "regex_check: $regexcheck" : '' ) . "\n" if $Cpanel::Debug::level;

            require Cpanel::CachedCommand::Save;
            Cpanel::CachedCommand::Save::_savefile( $datastore_file, $res );
        }
        else {
            print STDERR "_cached_command: failed regex check NOT writing datastore file: $datastore_file " . ( $regexcheck ? "regex_check: $regexcheck" : '' ) . "\n" if $Cpanel::Debug::level;
        }
    }

    return _cache_res_if_needed( $res, $ttl, $datastore_file, $data_mtime );
}

sub _cache_res_if_needed {
    my ( $res, $ttl, $datastore_file, $data_mtime ) = @_;

    if ( ref $res ) {
        if ( $ttl && ( !defined $$res || length($$res) < 32768 ) ) { $MEMORY_CACHE{$datastore_file} = { 'mtime' => $data_mtime, 'contents' => $res }; }
        return $res;
    }
    else {
        if ( $ttl && ( !defined $res || length($res) < 32768 ) ) { $MEMORY_CACHE{$datastore_file} = { 'mtime' => $data_mtime, 'contents' => \$res }; }
        return \$res;
    }
}

sub _default_get_result_cr {
    my ($opts) = @_;

    return _get_cmd_output( 'program' => $opts->{binary}, 'args' => $opts->{args}, 'stderr' => \*STDERR );
}

# for tests!
sub _get_memory_cache {
    return \%MEMORY_CACHE;
}

# For tests!
sub _time {
    return time();
}

#Overridden in tests
sub _get_cmd_output {
    my (@key_val) = @_;

    # Having this throw an exception breaks various parts of the codebase.
    return eval {
        require Cpanel::SafeRun::Object;
        my $run = Cpanel::SafeRun::Object->new(@key_val);
        $run->stdout();
    };
}

################################################################
# EXPORTED SUBS
################################################################

sub has_cache {
    my ( $ttl, $bin, @AG ) = @_;
    my @SAFEAG = @AG;
    if ( scalar @SAFEAG > 3 ) {
        splice( @SAFEAG, 3 );
    }
    my $datastore_file = Cpanel::CachedCommand::Utils::_get_datastore_filename( $bin, @SAFEAG );
    return (
        Cpanel::CachedCommand::Valid::is_cache_valid(
            'datastore_file' => $datastore_file,
            'binary'         => $bin,
            'ttl'            => $ttl
        )
    ) ? 1 : 0;
}

sub cachedcommand {
    my ( $binary, @ARGS ) = @_;

    my $cache_ref = _cached_cmd(
        'binary'     => $binary,
        'regexcheck' => qr/./,     # only cache data that actually exists
        'args'       => \@ARGS
    );
    if ( ref $cache_ref eq 'SCALAR' ) { return $$cache_ref; }
    return $cache_ref;
}

sub cachedcommand_no_errors {
    my (%OPTS) = @_;

    return _cached_cmd(
        binary => $OPTS{'binary'},
        args   => $OPTS{'args'},
        ( defined $OPTS{'mtime'} ? ( mtime => $OPTS{'mtime'} ) : () ),
        ( defined $OPTS{'ttl'}   ? ( ttl   => $OPTS{'ttl'} )   : () ),
        get_result_cr => sub {
            my ($opts) = @_;

            return _get_cmd_output( 'program' => $opts->{binary}, 'args' => $opts->{args}, ( $OPTS{ttl} ? ( 'timeout' => $OPTS{ttl}, 'read_timeout' => $OPTS{ttl} ) : () ) );
        }
    );
}

sub cachedcommand_multifile {
    my ( $test_file_ar, $binary, @ARGS ) = @_;
    my ( $mtime, $ctime ) = Cpanel::StatCache::cachedmtime_ctime($binary);
    if ( $ctime > $mtime ) {
        $mtime = $ctime;
    }
    foreach my $file (@$test_file_ar) {
        my @test_times = Cpanel::StatCache::cachedmtime_ctime($file);
        foreach my $new_time (@test_times) {
            if ( $new_time > $mtime ) {
                $mtime = $new_time;
            }
        }
    }
    my $cache_ref = _cached_cmd(
        'binary' => $binary,
        'args'   => \@ARGS,
        'mtime'  => $mtime
    );
    if ( ref $cache_ref eq 'SCALAR' ) { return $$cache_ref; }
    return $cache_ref;
}

sub cachedmcommand {
    my ( $ttl, $binary, @ARGS ) = @_;
    my $cache_ref = _cached_cmd(
        'ttl'    => $ttl,
        'binary' => $binary,
        'args'   => \@ARGS
    );
    if ( ref $cache_ref eq 'SCALAR' ) { return $$cache_ref; }
    return $cache_ref;
}

sub cachedmcommand_r_cleanenv {
    my ( $ttl, $binary, @ARGS ) = @_;
    my $cache_ref = _cached_cmd(
        'ttl'           => $ttl,
        'binary'        => $binary,
        'args'          => \@ARGS,
        'get_result_cr' => sub {
            my ($opts) = @_;

            require Cpanel::SafeRun::Env;
            return Cpanel::SafeRun::Env::saferun_r_cleanenv( $opts->{binary}, @{ $opts->{args} } );
        },
    );
    if ( ref $cache_ref ne 'SCALAR' ) { return \$cache_ref; }
    return $cache_ref;
}

sub cachedmcommand_cleanenv2 {
    my ( $ttl, $args_hr ) = @_;
    my @cmd       = @{ $args_hr->{'command'} };
    my $binary    = shift @cmd;
    my @ARGS      = @cmd;
    my $cache_ref = _cached_cmd(
        'ttl'           => $ttl,
        'binary'        => $binary,
        'args'          => \@ARGS,
        'get_result_cr' => sub {

            require Cpanel::SafeRun::Env;
            return Cpanel::SafeRun::Env::saferun_cleanenv2($args_hr);
        },
    );
    return $cache_ref;
}

sub cachedmcommand_r {
    my ( $ttl, $binary, @ARGS ) = @_;
    my $cache_ref = _cached_cmd(
        'ttl'    => $ttl,
        'binary' => $binary,
        'args'   => \@ARGS
    );
    if ( ref $cache_ref ne 'SCALAR' ) { return \$cache_ref; }
    return $cache_ref;
}

sub cachedmcommand2 {
    my $arg_ref = shift;

    my $bin        = $arg_ref->{'bin'};
    my $ttl        = $arg_ref->{'age'};
    my $timer      = $arg_ref->{'timer'};
    my $exact      = $arg_ref->{'exact'};
    my $regexcheck = $arg_ref->{'regexcheck'};
    my @AG         = @{ $arg_ref->{'ARGS'} };

    my $cache_ref = _cached_cmd(
        'binary'        => $bin,
        'ttl'           => $ttl,
        'exact'         => $exact,
        'regexcheck'    => $regexcheck,
        'args'          => \@AG,
        'get_result_cr' => sub {
            my ($opts) = @_;

            return _get_cmd_output( 'program' => $opts->{binary}, 'args' => $opts->{'args'}, 'stderr' => \*STDERR, ( int($timer) > 0 ? ( 'timeout' => $timer, 'read_timeout' => $timer ) : () ) );
        },
    );
    if ( ref $cache_ref eq 'SCALAR' ) { return $$cache_ref; }
    return $cache_ref;
}

sub noncachedcommand {
    my ( $bin, @AG ) = @_;

    if ( substr( $bin, 0, 1 ) eq '/' && !-x $bin ) {
        return "$bin is missing or not executable";
    }
    my $datastore_file = Cpanel::CachedCommand::Utils::_get_datastore_filename( $bin, $AG[0] );

    # Remove data store file because if this func is called
    # either the data store is corrupt or we don't want cached
    # results.
    if ( -e $datastore_file ) {
        unlink $datastore_file;
    }

    return _get_cmd_output( 'program' => $bin, 'args' => \@AG );
}

sub retrieve {
    my %OPTS = @_;
    return Cpanel::LoadFile::loadfile( Cpanel::CachedCommand::Utils::_get_datastore_filename( $OPTS{'name'} ) );
}

sub clear_memory_cache {
    %MEMORY_CACHE = ();
}

1;
