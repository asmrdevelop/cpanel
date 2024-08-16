package Cpanel::ConfigFiles::Apache::modules;

# cpanel - Cpanel/ConfigFiles/Apache/modules.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

######################################################################################################
#### This module is a modified version of EA3’s distiller’s code, it will be cleaned up via ZC-5317 ##
######################################################################################################

use strict;
use warnings;

use Cpanel::FileUtils::Dir ();
use Cpanel::ConfigFiles::Apache 'apache_paths_facade';    # see POD for import specifics
use Cpanel::Debug       ();
use Cpanel::GlobalCache ();
use Cpanel::LoadModule  ();
use Cpanel::StatCache   ();

my %options_support     = ();
my %compiled_support    = ();
my %shared_objects      = ();
my %memory_cache_mtimes = ( 'options_support' => 0, 'compiled_support' => 0, 'shared_objects' => 0 );

my $HTTPD_TIME = 0;                                       # This stores the last modification time of the httpd binary.
                                                          # It's stored globally so that it can be periodically updated
                                                          # by each of the caching subroutines,   The effect is, we can
                                                          # update each individual cache as needed, and not all at the
                                                          # same time.

sub is_supported {
    my $module = shift;
    $module =~ s/\.(?:c|so)$//;
    my $compiled_ref = get_compiled_support();
    if ( exists $compiled_ref->{ $module . '.c' } ) {
        return 1;
    }
    if ( has_shared_object($module) ) {
        return 1;
    }
    return;
}

sub get_supported_modules {
    my %supported = ();

    my $compiled = get_compiled_support();
    my $dso      = get_shared_objects();

    for my $dotc ( keys %{$compiled} ) {
        $dotc =~ s/\.c\Z//;
        $supported{$dotc} = 1;
    }

    for my $so ( keys %{$dso} ) {
        $so =~ s/\.so\Z//;
        $supported{$so} = 1;
    }

    return \%supported;
}

sub _get_file_time {
    my ($file) = @_;

    my ( $mtime, $ctime ) = ( stat($file) )[ 9, 10 ];

    $mtime ||= 0;
    $ctime ||= 0;

    return ( $ctime > $mtime ) ? $ctime : $mtime;
}

sub get_compiled_support {
    $HTTPD_TIME = _get_file_time( apache_paths_facade->bin_httpd() ) || 0;

    # return memory version if it hasn't expired yed
    if ( scalar keys %compiled_support && $memory_cache_mtimes{'compiled_support'} >= $HTTPD_TIME ) {
        return wantarray ? %compiled_support : \%compiled_support;
    }

    # memory cache expired, pull global cache from disk, and store into memory if it hasn't
    # expired too
    my $cached_compiled_support = Cpanel::GlobalCache::data( 'cpanel', 'Cpanel::ConfigFiles::Apache::modules::_get_compiled_support', $HTTPD_TIME );
    if ($cached_compiled_support) {
        $memory_cache_mtimes{'compiled_support'} = $HTTPD_TIME;
        %compiled_support = %$cached_compiled_support;
        return wantarray ? %compiled_support : \%compiled_support;
    }

    # nothing cached or everything expired... retrieve info and cache into memory
    # NOTE: We do not update the disk version of the cache.  That's handled by
    # bin/build_global_cache.
    goto &_get_compiled_support;
}

sub _get_compiled_support {
    %compiled_support = ();
    Cpanel::LoadModule::load_perl_module('Cpanel::CachedCommand');
    foreach my $line ( split( /\n/, Cpanel::CachedCommand::cachedcommand( apache_paths_facade->bin_httpd(), '-l' ) ) ) {
        if ( $line =~ m/is missing or not executable/ ) {
            delete @compiled_support{ keys %compiled_support };
            return;
        }
        elsif ( $line =~ m/^\s+(\S+)/ ) {
            $compiled_support{$1} = 1;
            if ( $1 eq 'mod_suexec.c' ) {
                $compiled_support{'suexec'} = 1;
            }
        }
        elsif ( $line =~ m/^\s*suexec:\s+(\S+);/ ) {
            $compiled_support{'suexec'} = lc $1 eq 'enabled' ? 1 : 0;
        }

    }
    $memory_cache_mtimes{'compiled_support'} = $HTTPD_TIME;
    return wantarray ? %compiled_support : \%compiled_support;
}

sub get_shared_objects {
    $HTTPD_TIME = _get_file_time( apache_paths_facade->bin_httpd() ) || 0;
    if ( scalar keys %shared_objects && $memory_cache_mtimes{'shared_objects'} >= $HTTPD_TIME ) {
        return wantarray ? %shared_objects : \%shared_objects;
    }
    %shared_objects = ();
    my $dir = get_so_dir();
    if ( opendir my $shared_dh, apache_paths_facade->dir_base() . '/' . $dir ) {
        %shared_objects = map { substr( $_, -3 ) eq '.so' ? ( $_ => 1 ) : () } readdir $shared_dh;
    }
    $memory_cache_mtimes{'shared_objects'} = $HTTPD_TIME;
    return wantarray ? %shared_objects : \%shared_objects;
}

sub has_shared_object {
    my $so = shift;
    $so =~ s/\.(?:c|so)$//;
    if ( -e apache_paths_facade->dir_base() . '/' . get_so_dir() . '/' . $so . '.so' ) {
        return 1;
    }
    return;
}

sub get_so_dir {
    my $options_ref = get_options_support();
    if ( !scalar keys %$options_ref || $options_ref->{'version'} lt '2' ) {
        return 'libexec';
    }
    return 'modules';
}

sub get_options_support {
    $HTTPD_TIME = _get_file_time( apache_paths_facade->bin_httpd() ) || 0;

    # return memory version if it hasn't expired yed
    if ( scalar keys %options_support && $memory_cache_mtimes{'options_support'} >= $HTTPD_TIME ) {
        return wantarray ? %options_support : \%options_support;
    }

    # memory cache expired, pull  global cache from disk, and store into memory if it hasn't
    # expired too
    my $mtime                  = Cpanel::StatCache::cachedmtime( apache_paths_facade->bin_httpd() );
    my $cached_options_support = Cpanel::GlobalCache::data( 'cpanel', 'Cpanel::ConfigFiles::Apache::modules::_get_options_support', $HTTPD_TIME );
    if ($cached_options_support) {
        $memory_cache_mtimes{'options_support'} = $HTTPD_TIME;
        %options_support = %$cached_options_support;
        return wantarray ? %options_support : \%options_support;
    }

    # nothing cached or everything expired... retrieve info and cache into memory
    # NOTE: We do not update the disk version of the cache.  That's handled by
    # bin/build_global_cache.
    goto &_get_options_support;
}

sub _get_options_support {
    %options_support = ();

    my $httpd = apache_paths_facade->bin_httpd();

    Cpanel::LoadModule::load_perl_module('Cpanel::CachedCommand');
    Cpanel::LoadModule::load_perl_module('Cpanel::Config::Httpd::EA4');
    my $buffer = Cpanel::CachedCommand::cachedcommand( $httpd, '-V' );
    if ( length($buffer) == 0 && Cpanel::Config::Httpd::EA4::is_ea4() ) {
        Cpanel::CachedCommand::invalidate_cache( $httpd, '-V' );

        # if httpd -V returns an empty string, that means the config file is
        # corrupt or non existent.  scripts/rebuildhttpdconf will not work
        # in this situation.
        #
        # in EA4 we have some options
        #
        # create a minimal httpd.conf to allow this call to complete
        # But we need to find out which mpm is available.
        #
        # If we have to use this approach, build the getversion httpd.conf
        # each time in case they change which MPM is installed via rpm.
        #
        # Once the httpd.conf is solid this code is no longer used.

        Cpanel::LoadModule::load_perl_module('Cpanel::TempFile');
        my $temp_obj = Cpanel::TempFile->new();
        my ( $temp_file, $temp_fh ) = $temp_obj->file();

        my $cfobj       = Cpanel::ConfigFiles::Apache->new();
        my $dir_modules = $cfobj->dir_modules();
        my $module;

        foreach my $xmodule ( @{ Cpanel::FileUtils::Dir::get_directory_nodes($dir_modules) } ) {
            if ( $xmodule =~ m{^mod_(mpm_.*)\.so$} ) {
                $module = $1;
            }
        }

        if ( defined $module ) {

            # use a temporary variable for perltidy
            my $loadmodule = qq{

LoadModule ${module}_module modules/mod_$module.so
};

            print {$temp_fh} $loadmodule;
            close $temp_fh;

            $buffer = `$httpd -V -f $temp_file`;
        }
    }

    if ( length($buffer) == 0 ) {
        Cpanel::CachedCommand::invalidate_cache( $httpd, '-V' );

        # if buffer is empty one of many problems could be causing it
        # including no httpd.conf, syntax error in httpd.conf or even no MPM
        # loaded, yet syntactically correct.

        Cpanel::Debug::log_warn("Invalid Apache Config File, $httpd");
        %options_support = ();
        return;
    }

    my @lines = split( /\n/, $buffer );
    foreach my $line (@lines) {
        if ( $line =~ m/is missing or not executable/ ) {
            %options_support = ();
            return;
        }
        elsif ( $line =~ m/^\s*Server\s+version:\s+Apache\/([\d.]+)/i ) {
            $options_support{'version'}       = $1;
            $options_support{'split_version'} = [ split /\./, $1 ];
        }
        elsif ( $line =~ m/^\s*Server\s+built:\s+(.+)/ ) {
            $options_support{'build'} = $1;
        }
        elsif ( $line =~ m/^\s*Server\s+MPM:\s*(\w+)/i ) {
            $options_support{'mpm'} = lc $1;
        }
        elsif ( $line =~ m/^\s*-D\s+(\S+)/ ) {
            my $value = $1;
            if ( $value =~ m/(\S+)="?([^\s"]+)"?\s*/ ) {
                $options_support{$1} = $2;
            }
            else {
                $options_support{$value} = 1;
            }
            if ( $value eq 'APR_HAVE_IPV6' ) {
                $options_support{'v4-mapped'} = $line =~ /enabled/ ? 1 : 0;
            }
        }
    }
    $memory_cache_mtimes{'options_support'} = $HTTPD_TIME;
    return wantarray ? %options_support : \%options_support;
}

sub apache_mpm_threaded {
    my $options_ref = _get_options_support();

    my $mpm = $options_ref->{'mpm'} // '';

    if ( $mpm eq 'worker' || $mpm eq 'event' ) {
        return 1;
    }

    return 0;
}

# Short version, e.g. '1' or '2'
sub apache_short_version {
    return apache_version( { 'places' => 1 } );
}

# Long version, e.g. '2.2.22'
sub apache_long_version {
    my $options_ref = get_options_support();
    return $options_ref->{'version'};
}

# Get the Apache version string
# optional arg is a hash controlling the format of the version string. Keys:
# separator - character separating parts of the version (default is '_')
# places - number of version parts to keep (1, 2, and 3 yield '1', '1.2', '1.2.33'; 0 = all, default = 2)
# trim_zeroes - remove trailing zero parts (e.g., convert '1.0.00' to '1'; default false)
sub apache_version {
    my ($opt) = @_;
    $opt                = {} if ( !$opt );
    $opt->{'separator'} = '_' unless defined $opt->{'separator'};
    $opt->{'places'}    = 2   unless defined $opt->{'places'};

    my $longver = apache_long_version();
    return '' unless defined $longver;

    my @version = split( /\./, $longver );
    @version = @version[ 0 .. $opt->{'places'} - 1 ] if $opt->{'places'};

    if ( $opt->{'trim_zeroes'} ) {
        pop @version while ( @version > 1 && $version[-1] =~ /^0+$/ );
    }
    @version = grep { defined($_) } @version;    # Filter out undef values
    return join( $opt->{'separator'}, @version );
}

sub get_module_url {
    my $uri_version = shift;
    my $module      = shift;
    my $link        = shift;
    $link = lc $link;
    return "http://httpd.apache.org/docs/$uri_version/mod/$module.html#$link";
}

sub clean_module_caches {
    %options_support     = ();
    %compiled_support    = ();
    %shared_objects      = ();
    %memory_cache_mtimes = ( 'options_support' => 0, 'compiled_support' => 0, 'shared_objects' => 0 );
    $HTTPD_TIME          = 0;

    return;
}

1;
