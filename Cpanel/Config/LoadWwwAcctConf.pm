package Cpanel::Config::LoadWwwAcctConf;

# cpanel - Cpanel/Config/LoadWwwAcctConf.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::HiRes ();

use Cpanel::Path::Normalize ();
use Cpanel::Debug           ();
use Cpanel::JSON::FailOK    ();

my $SYSTEM_CONF_DIR = '/etc';
my $wwwconf_cache;
my $wwwconf_mtime = 0;

my $has_serializer;

our $wwwacctconf       = "$SYSTEM_CONF_DIR/wwwacct.conf";
our $wwwacctconfshadow = "$SYSTEM_CONF_DIR/wwwacct.conf.shadow";

sub import {
    my $this = shift;
    if ( !exists $INC{'Cpanel/JSON.pm'} ) {
        Cpanel::JSON::FailOK::LoadJSONModule();
    }
    if ( $INC{'Cpanel/JSON.pm'} ) {
        $has_serializer = 1;
    }
    return Exporter::import( $this, @_ );
}

sub loadwwwacctconf {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    if ( $INC{'Cpanel/JSON.pm'} ) { $has_serializer = 1; }    #something else loaded it

    my $filesys_mtime = ( Cpanel::HiRes::stat($wwwacctconf) )[9];

    return if !$filesys_mtime;

    #memory cache
    if ( $filesys_mtime == $wwwconf_mtime && $wwwconf_cache ) {
        return wantarray ? %{$wwwconf_cache} : $wwwconf_cache;
    }

    my $wwwacctconf_cache       = "$wwwacctconf.cache";
    my $wwwacctconfshadow_cache = "$wwwacctconfshadow.cache";
    my $is_root                 = $> ? 0 : 1;

    #Cpanel::JSON cache
    if ($has_serializer) {
        my $cache_file;
        my $cache_filesys_mtime;
        my $have_valid_cache = 1;

        #root, and we have shadow cache (which has everything): use shadow cache
        if ( $is_root && -e $wwwacctconfshadow_cache ) {
            $cache_filesys_mtime = ( Cpanel::HiRes::stat($wwwacctconfshadow_cache) )[9];    #shadow cache's mtime

            #be sure the shadow file hasn't been updated more recently than its cache
            #we check for wwwacct.conf's mtime below
            my $shadow_file_mtime = ( Cpanel::HiRes::stat $wwwacctconfshadow )[9] || 0;
            if ( $shadow_file_mtime < $cache_filesys_mtime ) {
                $cache_file = $wwwacctconfshadow_cache;
            }
            else {    #don't use shadow cache if shadow file is newer
                $have_valid_cache = undef;
            }
        }

        #have regular cache, and either non-root or no shadow file: use regular cache
        elsif ( -e $wwwacctconf_cache && !( $is_root && -r $wwwacctconfshadow ) ) {
            $cache_filesys_mtime = ( Cpanel::HiRes::stat $wwwacctconf_cache )[9];    #regular cache's mtime
            $cache_file          = $wwwacctconf_cache;
        }
        else {
            $have_valid_cache = undef;
        }
        my $now = Cpanel::HiRes::time();

        if ( $Cpanel::Debug::level >= 5 ) {
            print STDERR __PACKAGE__ . "::loadwwwacctconf cache_filesys_mtime = $cache_filesys_mtime , filesys_mtime: $filesys_mtime , now : $now\n";
        }

        #check cache (whichever) against
        if ( $have_valid_cache && $cache_filesys_mtime > $filesys_mtime && $cache_filesys_mtime < $now ) {
            my $wwwconf_ref;
            if ( open( my $conf_fh, '<', $cache_file ) ) {
                $wwwconf_ref = Cpanel::JSON::FailOK::LoadFile($conf_fh);
                close($conf_fh);
            }

            if ( $wwwconf_ref && ( scalar keys %{$wwwconf_ref} ) > 0 ) {
                if ( $Cpanel::Debug::level >= 5 ) { print STDERR __PACKAGE__ . "::loadwwwconf file system cache hit\n"; }
                $wwwconf_cache = $wwwconf_ref;
                $wwwconf_mtime = $filesys_mtime;
                return wantarray ? %{$wwwconf_ref} : $wwwconf_ref;
            }
        }
    }

    # Process both wwwacct files
    my @configfiles;
    push @configfiles, $wwwacctconf;

    #SECURITY: any refactor of this will require major auditting
    if ($is_root) { push @configfiles, $wwwacctconfshadow; }    #shadow file must be last as the cache gets written for each file with all the files before it in it

    my $can_write_cache;
    if ( $is_root && $has_serializer ) {
        $can_write_cache = 1;
    }

    # Only list mandatory options.
    my %CONF = (
        'ADDR'         => undef,
        'CONTACTEMAIL' => undef,
        'DEFMOD'       => undef,
        'ETHDEV'       => undef,
        'HOST'         => undef,
        'NS'           => undef,
        'NS2'          => undef,
    );
    require Cpanel::Config::LoadConfig;
    foreach my $configfile (@configfiles) {
        Cpanel::Config::LoadConfig::loadConfig( $configfile, \%CONF, '\s+', undef, undef, undef, { 'nocache' => 1 } );

        foreach ( keys %CONF ) {

            # Trim trailing whitespace from all values
            $CONF{$_} =~ s{\s+$}{} if defined $CONF{$_};
        }

        $CONF{'HOMEMATCH'} =~ s{/+$}{} if defined $CONF{'HOMEMATCH'};    # Remove trailing slashes

        $CONF{'HOMEDIR'} = Cpanel::Path::Normalize::normalize( $CONF{'HOMEDIR'} ) if defined $CONF{'HOMEDIR'};

        if ($can_write_cache) {
            my $cache_file = $configfile . '.cache';
            require Cpanel::FileUtils::Write::JSON::Lazy;
            Cpanel::FileUtils::Write::JSON::Lazy::write_file( $cache_file, \%CONF, ( $configfile eq $wwwacctconfshadow ) ? 0600 : 0644 );
        }
    }

    $wwwconf_mtime = $filesys_mtime;
    $wwwconf_cache = \%CONF;

    return wantarray ? %CONF : \%CONF;
}

sub reset_mem_cache {
    ( $wwwconf_mtime, $wwwconf_cache ) = ( 0, undef );
}

sub reset_has_serializer {
    $has_serializer = 0;
}

sub default_conf_dir {
    $SYSTEM_CONF_DIR = shift if @_;

    $wwwacctconf       = "$SYSTEM_CONF_DIR/wwwacct.conf";
    $wwwacctconfshadow = "$SYSTEM_CONF_DIR/wwwacct.conf.shadow";

    return $SYSTEM_CONF_DIR;
}

sub reset_caches {
    my @cache_files = map { "$_.cache" } ( $wwwacctconf, $wwwacctconfshadow );

    for my $cache_file (@cache_files) {
        unlink $cache_file if -e $cache_file;
    }

    reset_mem_cache();

    return;
}

1;
