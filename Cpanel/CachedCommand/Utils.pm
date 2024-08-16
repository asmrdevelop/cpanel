package Cpanel::CachedCommand::Utils;

# cpanel - Cpanel/CachedCommand/Utils.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Cpanel::SV ();

my ( $cached_datastore_myuid, $cached_datastore_dir );

sub destroy {
    my %OPTS       = @_;
    my $cache_file = _get_datastore_filename( $OPTS{'name'}, ( $OPTS{'args'} ? @{ $OPTS{'args'} } : () ) );
    if ( -e $cache_file ) {
        return unlink $cache_file;
    }
    else {
        return 1;
    }
    return;
}

*get_datastore_filename = *_get_datastore_filename;

sub _get_datastore_filename {
    my ( $bin, @args ) = @_;

    my $file = join( '_', $bin, @args );
    $file =~ tr{/}{_};
    Cpanel::SV::untaint($file);

    my $datastore_dir = _get_datastore_dir($file);
    Cpanel::SV::untaint($datastore_dir);

    return $datastore_dir . '/' . $file;
}

sub _get_datastore_dir {
    my $file  = shift;
    my $myuid = $>;

    if ( defined $cached_datastore_dir && length $cached_datastore_dir > 1 && $myuid == $cached_datastore_myuid ) {
        my $homedir = Cpanel::PwCache::gethomedir();
        $cached_datastore_dir = "$homedir/$ENV{'TEAM_USER'}/.cpanel/datastore" if $ENV{'TEAM_USER'} && $file =~ /^AVAILABLE_APPLICATIONS_CACHE/;
        return $cached_datastore_dir;
    }

    require Cpanel::PwCache;
    $cached_datastore_dir = Cpanel::SV::untaint( Cpanel::PwCache::gethomedir() );
    $cached_datastore_dir .= "/$ENV{'TEAM_USER'}" if $ENV{'TEAM_USER'} && $file =~ /^AVAILABLE_APPLICATIONS_CACHE/;

    if ( !-e $cached_datastore_dir . '/.cpanel/datastore' && $cached_datastore_dir ne '/' ) {    # nobody's homedir is /
        require Cpanel::SafeDir::MK;
        Cpanel::SafeDir::MK::safemkdir( "$cached_datastore_dir/.cpanel/datastore", 0700 ) or warn "Failed to mkdir($cached_datastore_dir/.cpanel/datastore): $!";
    }

    $cached_datastore_myuid = $myuid;
    $cached_datastore_dir .= '/.cpanel/datastore';
    return $cached_datastore_dir;
}

sub invalidate_cache {
    my $ds_file = get_datastore_filename(@_);
    unlink $ds_file;
    return $ds_file;
}

sub clearcache {
    $cached_datastore_dir   = undef;
    $cached_datastore_myuid = undef;
    return;
}

1;
