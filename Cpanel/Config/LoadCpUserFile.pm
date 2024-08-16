package Cpanel::Config::LoadCpUserFile;

# cpanel - Cpanel/Config/LoadCpUserFile.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Config::LoadCpUserFile

=cut

use Try::Tiny;

use Cpanel::DB::Utils                    ();
use Cpanel::Exception                    ();
use Cpanel::FileUtils::Write::JSON::Lazy ();
use Cpanel::AdminBin::Serializer::FailOK ();
use Cpanel::Config::Constants            ();
use Cpanel::Config::CpUser::Defaults     ();
use Cpanel::Config::CpUser::Object       ();
use Cpanel::ConfigFiles                  ();
use Cpanel::LoadFile::ReadFast           ();
use Cpanel::SV                           ();

our $VERSION = '0.82';    # DO NOT CHANGE THIS FROM A DECIMAL

#used in testing only
sub _cpuser_defaults {
    return @Cpanel::Config::CpUser::Defaults::DEFAULTS_KV;
}

my %should_never_be_on_disk = map { $_ => undef } qw(
  DBOWNER
  DOMAIN
  DOMAINS
  DEADDOMAINS
  HOMEDIRLINKS
);

my $logger;

#----------------------------------------------------------------------

=head1 FUNCTIONS

=cut

#
#   Read the contents of the given user's cpuser file.
#
sub load_or_die {
    return ( _load( $_[0], undef, if_missing => 'die' ) )[2];
}

sub load_if_exists {
    return ( _load( $_[0], undef, if_missing => 'return' ) )[2] // undef;
}

#Use this to load an arbitrary file as a cpuser file.
sub load_file {
    my ($file) = @_;

    # Do not use a safefile lock since
    # it would just be released right
    # after the read anyways.

    return parse_cpuser_file( _open_cpuser_file( '<', $file ) );
}

sub _open_cpuser_file_locked {
    my ( $mode, $file ) = @_;

    local $!;

    my $cpuser_fh;

    require Cpanel::SafeFile;
    my $lock_obj = Cpanel::SafeFile::safeopen( $cpuser_fh, $mode, $file ) or do {
        die Cpanel::Exception::create( 'IO::FileOpenError', [ path => $file, error => $!, mode => $mode ] );
    };

    return ( $lock_obj, $cpuser_fh );
}

sub _open_cpuser_file {
    my ( $mode, $file ) = @_;

    local $!;

    my $cpuser_fh;

    # Users can open their own files, but they shouldn't have write perms on the dir so the .lock file will error
    open( $cpuser_fh, $mode, $file ) or do {
        die Cpanel::Exception::create( 'IO::FileOpenError', [ path => $file, error => $!, mode => $mode ] );
    };
    return $cpuser_fh;
}

sub parse_cpuser_file {
    my ($cpuser_fh) = @_;

    my $buffer = '';
    Cpanel::LoadFile::ReadFast::read_all_fast( $cpuser_fh, $buffer );

    return parse_cpuser_file_buffer($buffer);
}

=head2 $hr = parse_cpuser_file_buffer($BUFFER)

Parses $BUFFER as cpuser file contents and returns a
L<Cpanel::Config::CpUser::Object> instance that
represents the results of that parse.

=cut

sub parse_cpuser_file_buffer {
    my ($buffer) = @_;

    my %cpuser = _cpuser_defaults();

    # temporary hashes to avoid slow grep()
    my %DOMAIN_MAP;
    my %DEAD_DOMAIN_MAP;
    my %HOMEDIRLINKS_MAP;

    local ( $!, $_ );

    foreach ( split( m{\n}, $buffer ) ) {
        next if index( $_, '#' ) > -1 && m/^\s*#/;

        # No chomp here since we split on \n
        my ( $key, $value ) = split( /\s*=/, $_, 2 );

        if ( !defined $value || exists $should_never_be_on_disk{$key} ) {
            next;

        }
        elsif ( $key eq 'DNS' ) {
            $cpuser{'DOMAIN'} = lc $value;
        }

        # This is just a light check for (X)?DNS with any number following it
        # It should not be possible for DNS1xxx to appear in the file
        # since we control the file end to end.
        elsif ( index( $key, 'DNS' ) == 0 && substr( $key, 3, 1 ) =~ tr{0-9}{} ) {
            $DOMAIN_MAP{ lc $value } = undef;
        }
        elsif ( index( $key, 'XDNS' ) == 0 && substr( $key, 4, 1 ) =~ tr{0-9}{} ) {
            $DEAD_DOMAIN_MAP{ lc $value } = undef;
        }
        elsif ( index( $key, 'HOMEDIRPATHS' ) == 0 && $key =~ m{ \A HOMEDIRPATHS \d* \z }xms ) {
            $HOMEDIRLINKS_MAP{$value} = undef;
        }
        else {
            $cpuser{$key} = $value;
        }
    }

    delete @DEAD_DOMAIN_MAP{ keys %DOMAIN_MAP };
    delete $DOMAIN_MAP{ $cpuser{'DOMAIN'} };

    if ($!) {
        die Cpanel::Exception::create( 'IO::FileReadError', [ error => $! ] );
    }

    if ( exists $cpuser{'USER'} ) {

        #We used to save this value in the file prior to 11.44.
        $cpuser{'DBOWNER'} = Cpanel::DB::Utils::username_to_dbowner( $cpuser{'USER'} );
    }

    # Set the theme(RS) to default theme if its not set from the user file.
    if ( !length $cpuser{'RS'} ) {
        require Cpanel::Conf;
        my $cp_defaults = Cpanel::Conf->new();
        $cpuser{'RS'} = $cp_defaults->cpanel_theme;
    }

    # Ensure LOCALE is set, and set __LOCALE_MISSING if it is missing
    # so ULC/scripts/migrate_legacy_lang_to_locale knows to migrate it
    if ( !$cpuser{'LOCALE'} ) {
        $cpuser{'LOCALE'}           = 'en';
        $cpuser{'__LOCALE_MISSING'} = 1;
    }
    $cpuser{'DOMAINS'}      = [ sort keys %DOMAIN_MAP ];         # Sorted here so they can be tested with TM::is_deeply
    $cpuser{'DEADDOMAINS'}  = [ sort keys %DEAD_DOMAIN_MAP ];    # Sorted here so they can be tested with TM::is_deeply
    $cpuser{'HOMEDIRLINKS'} = [ sort keys %HOMEDIRLINKS_MAP ];

    return _wrap_cpuser( \%cpuser );
}

sub _wrap_cpuser {
    return Cpanel::Config::CpUser::Object->adopt(shift);
}

sub _logger {
    return $logger ||= do {
        require Cpanel::Logger;
        Cpanel::Logger->new();
    };
}

#Like load_or_die(), but doesn’t actually fail if the cpuser file
#isn’t there.
#
#   XXX: Wait!!! Before calling this, consider load_or_die().
#
sub load {
    my ( $user, $opts ) = @_;

    my $cpuser = ( _load( $user, $opts ) )[2];

    if ( !ref $cpuser ) {
        _logger()->warn( "Failed to load cPanel user file for '" . ( $user || '' ) . "'" ) unless $opts->{'quiet'};
        return wantarray ? () : bless( {}, 'Cpanel::Config::CpUser::Object' );
    }
    return wantarray ? %$cpuser : $cpuser;
}

#
#   Read the contents of the given user's cpuser file,
#   leaving the file open and locked for exclusive access
#
#   NOTE: Intended for use by the Cpanel::Config::CpUserGuard class.
#   Nothing else should call this function.
#
sub _load_locked {
    my ($user) = @_;

    my ( $fh, $lock_fh, $cpuser ) = _load( $user, { lock => 1 } );

    return unless $fh && $lock_fh && $cpuser;

    return {
        'file' => $fh,
        'lock' => $lock_fh,
        'data' => $cpuser,
    };
}

sub clear_cache {
    my ($user) = @_;

    return unlink "$Cpanel::ConfigFiles::cpanel_users.cache/$user";
}

#
#   Currently supports one option:
#       lock (boolean): hold the lock on the cpusers file, and return the file and lock handles
#
#   The return is in three parts:
#       filehandle (r/w), OR undef if !lock
#       lock object, OR undef if !lock
#       cpuser data (hashref)
#
#   %internal_opts is for private options to pass into here.
#   If $internal_opts{'if_missing'} eq 'die', then we’ll
#   throw an exception. If that value is 'return', then we return
#   if the cpuser file is missing but still throw an exception
#   if we fail to determine if the file is missing.
#
#   On error this returns nothing and logs the error.
#
sub _load {    ## no critic(Subroutines::ProhibitExcessComplexity)  -- Refactoring this function is a project, not a bug fix
    my ( $user, $load_opts_ref, %internal_opts ) = @_;

    if ( !$user || $user =~ tr</\0><> ) {    #no eq '' needed as !$user covers this
        _logger()->warn("Invalid username (falsy or forbidden character) given to loadcpuserfile.");

        # Even if “if_missing” isn’t “die”, throw an exception since
        # we really shouldn’t get here. We assume that the code paths
        # that call the functions that set this flag expect exceptions.
        if ( $internal_opts{'if_missing'} ) {
            die Cpanel::Exception::create( 'UserNotFound', [ name => '' ] );
        }

        return;
    }

    my ( $now, $has_serializer, $user_file, $user_cache_file ) = (
        time(),                                                                    #now
        ( exists $INC{'Cpanel/JSON.pm'} ? 1 : 0 ),                                 #has_serializer
        $load_opts_ref->{'file'} || "$Cpanel::ConfigFiles::cpanel_users/$user",    # user_file
        "$Cpanel::ConfigFiles::cpanel_users.cache/$user",                          # user_cache_file
    );

    my ( $cpuid, $cpgid, $size, $mtime ) = ( stat($user_file) )[ 4, 5, 7, 9 ];

    if ( not defined($size) and my $if_missing = $internal_opts{'if_missing'} ) {
        if ( $! == _ENOENT() ) {
            if ( $if_missing eq 'return' ) {
                return;
            }

            die Cpanel::Exception::create( 'UserNotFound', [ name => $user ] );
        }
        die Cpanel::Exception->create( 'The system failed to find the file “[_1]” because of an error: [_2]', [ $user_file, $! ] );
    }

    $mtime ||= 0;

    my $lock_fh;
    my $cpuser_fh;

    if ( $load_opts_ref->{'lock'} ) {
        my $mode = $mtime ? '+<' : '+>';
        try {
            # Only obtain a SafeFile lock if requested
            ( $lock_fh, $cpuser_fh ) = _open_cpuser_file_locked( $mode, $user_file );
        }
        catch {
            if ( my $if_missing = $internal_opts{'if_missing'} ) {
                die $_ if $if_missing ne 'return';
            }
            else {
                _logger()->warn($_);
            }
        };

        return if !$lock_fh;
    }
    elsif ( !$size ) {
        if ( $user eq 'cpanel' ) {
            my $result = _load_cpanel_user();
            _wrap_cpuser($result);
            return ( $cpuser_fh, $lock_fh, $result );
        }
        else {
            _logger()->warn("User file '$user_file' is empty or non-existent.") unless $load_opts_ref->{'quiet'};
            return;
        }
    }

    if ( $Cpanel::Debug::level && $Cpanel::Debug::level > 3 ) {    # PPI NO PARSE - This doesn't need to be loaded
        _logger()->debug("load cPanel user file [$user]");
    }

    if ($has_serializer) {
        Cpanel::SV::untaint($user_cache_file);                        # case CPANEL-11199
        if ( open( my $cache_fh, '<:stdio', $user_cache_file ) ) {    #ok if the file is not there
            my $cache_mtime = ( stat($cache_fh) )[9];                 # Check the mtime after we have opened the file to prevent a race condition
            if ( $cache_mtime >= $mtime && $cache_mtime <= $now ) {
                my $cpuser_ref = Cpanel::AdminBin::Serializer::FailOK::LoadFile($cache_fh);
                if ( $cpuser_ref && ref $cpuser_ref eq 'HASH' ) {
                    if ( $Cpanel::Debug::level && $Cpanel::Debug::level > 3 ) {    # PPI NO PARSE - This doesn't need to be loaded
                        _logger()->debug("load cache hit user[$user] now[$now] mtime[$mtime] cache_mtime[$cache_mtime]");
                    }
                    $cpuser_ref->{'MTIME'} = $mtime;

                    # The __CACHE_DATA_VERSION key/logic helps ensure the cached data has been
                    # processed via the sanitizing logic that happens on the initial load - See case 44087
                    # for an example of why this need done
                    #
                    # We also assume the cache is invalid if the DOMAIN is missing
                    if ( ( $cpuser_ref->{'__CACHE_DATA_VERSION'} // 0 ) == $VERSION ) {
                        _wrap_cpuser($cpuser_ref);
                        return ( $cpuser_fh, $lock_fh, $cpuser_ref );
                    }
                    else {
                        unlink $user_cache_file;    # force a re-cache of the latest data set
                    }
                }
            }
            else {
                if ( $Cpanel::Debug::level && $Cpanel::Debug::level > 3 ) {    # PPI NO PARSE - This doesn't need to be loaded
                    _logger()->debug("load cache miss user[$user] now[$now] mtime[$mtime] cache_mtime[$cache_mtime]");
                }
            }
            close($cache_fh);
        }
        else {
            if ( $Cpanel::Debug::level && $Cpanel::Debug::level > 3 ) {    # PPI NO PARSE - This doesn't need to be loaded
                _logger()->debug("load cache miss user[$user] now[$now] mtime[$mtime] cache_mtime[0]");
            }
        }
    }

    if ( !$lock_fh ) {
        try {
            # Not called with the lock file.
            # Do not use a safefile lock since
            # it would just be released right
            # after the read anyways. THIS IS SAFE
            # ONLY AS LONG AS WE NEVER WRITE THE CPUSER
            # FILE ONCE IT IS IN PLACE. If we ever change from
            # that we’ll need a read/shared lock or some such.
            $cpuser_fh = _open_cpuser_file( '<', $user_file );
        }
        catch {
            die $_ if $internal_opts{'if_missing'};

            _logger()->warn($_);
        };

        return if !$cpuser_fh;
    }

    my $cpuser_hr;
    try {
        $cpuser_hr = parse_cpuser_file($cpuser_fh);
    }
    catch {
        _logger()->warn("Failed to read “$user_file”: $_");
    };

    return if !$cpuser_hr;

    $cpuser_hr->{'USER'}    = $user;
    $cpuser_hr->{'DBOWNER'} = Cpanel::DB::Utils::username_to_dbowner($user);

    $cpuser_hr->{'__CACHE_DATA_VERSION'} = $VERSION;    # set this before the cache is written so that it will be included in the cache
    if ( $> == 0 ) {
        create_users_cache_dir();
        if ( $has_serializer && Cpanel::FileUtils::Write::JSON::Lazy::write_file( $user_cache_file, $cpuser_hr, 0640 ) ) {
            chown 0, $cpgid, $user_cache_file if $cpgid;    # this is ok if the chown happens after as we fall though to reading the non-cache on a failed open
        }
        else {
            unlink $user_cache_file;                        #outdated
        }
    }

    $cpuser_hr->{'MTIME'} = ( stat($cpuser_fh) )[9];
    if ( $load_opts_ref->{'lock'} ) {
        seek( $cpuser_fh, 0, 0 );
    }
    else {
        if ($lock_fh) {
            require Cpanel::SafeFile;
            Cpanel::SafeFile::safeclose( $cpuser_fh, $lock_fh );
        }
        $cpuser_fh = $lock_fh = undef;
    }

    return ( $cpuser_fh, $lock_fh, $cpuser_hr );
}

# Compatibility function, ignores additional args to loadcpuserfile to call
# real 'load' function.
sub loadcpuserfile {
    return load( $_[0] );
}

sub _load_cpanel_user {
    my %cpuser = (
        _cpuser_defaults(),
        'DEADDOMAINS'  => [],
        'DOMAIN'       => 'domain.tld',
        'DOMAINS'      => [],
        'HASCGI'       => 1,
        'HOMEDIRLINKS' => [],
        'LOCALE'       => 'en',
        'MAXADDON'     => 'unlimited',
        'MAXPARK'      => 'unlimited',
        'RS'           => $Cpanel::Config::Constants::DEFAULT_CPANEL_THEME,
        'USER'         => 'cpanel',
    );

    return wantarray ? %cpuser : \%cpuser;
}

sub create_users_cache_dir {
    my $uc = "$Cpanel::ConfigFiles::cpanel_users.cache";
    if ( -f $uc || -l $uc ) {
        my $bad = "$uc.bad";
        unlink $bad if -e $bad;
        rename $uc, $bad;
    }
    if ( !-e $uc ) {
        mkdir $uc;
    }
    return;
}

sub _ENOENT { return 2; }

1;
