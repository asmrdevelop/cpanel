package Cpanel::NVData;

# cpanel - Cpanel/NVData.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Try::Tiny;

use Cpanel::Debug                ();
use Cpanel::Exception            ();
use Cpanel::StatCache            ();
use Cpanel::AdminBin::Serializer ();
use Cpanel::LoadFile             ();
use Cpanel::Encoder::Tiny        ();

use constant {
    _EDQUOT => 122,
};

# No need to use CachedDataStore as the data is stored in text dbs elsewhere and can be reloaded

our $VERSION = '1.6';

#This is only done to avoid caching large datasets from third party plugins.
#It is ok to increase in size to 512 if needed.
our $MAX_VALUE_LENGTH = 128;

my ( %NVDataCACHE, %GET_SAFE_NAME_CACHE );
our $NVCacheLoaded = 0;

sub NVData_init {
    return 1;
}

sub NVData_set {    ## no critic (RequireArgUnpacking)
    _set(@_);
    return;
}

sub NVData_get {
    my ($key) = @_;

    print _get($key);
    return;
}

sub getcpaneldir {
    my $homedir   = gethomedir();
    my $team_user = $ENV{TEAM_USER} ? "/$ENV{TEAM_USER}" : '';
    return $homedir . $team_user . '/.cpanel';
}

sub gethomedir {
    return ( $Cpanel::homedir || ( getpwuid $> )[7] );
}

sub getnvdir {
    return getcpaneldir() . '/nvdata';
}

sub _sanitize_name_if_needed {
    my ($name) = @_;

    if ( $name =~ tr</><> ) {
        my $orig = $name;
        $name =~ tr</><>d;
        warn "Treating key “$orig” as “$name” …";
    }

    return $name;
}

=head1 _set(NAME, VALUE, NOCACHE)

Protected implementation used to save a single name/value pair to a
its backing file location.  This method was designed to bypass api1 and
api2 specific handling that is not needed for newer api calls.

=head2 Arguments

=over

=item NAME

String - the key name to store the value under. This is used to build the
file name in /home/<user>/.cpanel/nvdata/<name>.

=item VALUE

String - the value to store for the name key.

=item NOCACHE

Boolean - Optional - If provided, allows you to bypass the caching if truthy.

=back

=head2 Returns

List with the following elements

(ERROR, PATH)

=over

=item ERROR

String - when its not empty, indicates the set failed.

=item PATH

String - full path to the output file if there is an error.

=back

=cut

sub _set {    ## no critic (RequireArgUnpacking)
    my ( $name, $value, $nocache ) = ( Cpanel::Encoder::Tiny::safe_xml_encode_str( $_[0] ), $_[1], $_[2] );

    $name = _sanitize_name_if_needed($name);

    my ( $cpaneldir, $nvdir ) = _dircheck();
    my $path = $nvdir . '/' . $name;

    return ( "$value for $name is not valid", $path ) unless _validate_name_is_valid( $name, $value );

    if ( open my $nvdata_fh, '>', $path ) {
        print {$nvdata_fh} $value or return ( $!, $path );
        close $nvdata_fh          or return ( $!, $path );

        # Update caches
        _loadcache() if !$NVCacheLoaded;
        $NVDataCACHE{$name}{'value'} = $value;
        $NVDataCACHE{$name}{'mtime'} = time();
        _savecache() if !$nocache && length $value <= $MAX_VALUE_LENGTH;
        return ( undef, undef );
    }
    else {
        my $exception = $!;
        Cpanel::Debug::log_warn("Unable to write nvdata file: $path: $exception");
        return ( $exception, $path );
    }
}

sub _savecache {
    my $cachefile = getcpaneldir() . '/nvdata.cache';

    #Only save keys of length <= $MAX_VALUE_LENGTH in the cache.
    #We’ll still load the longer keys; those will just have to come from
    #the source NVData files.
    try {
        require Cpanel::FileUtils::Write;
        Cpanel::FileUtils::Write::overwrite(
            $cachefile,
            Cpanel::AdminBin::Serializer::Dump(
                {
                    map    { $_ => $NVDataCACHE{$_} }                                                                        ## no critic (ProhibitVoidMap)
                      grep { !defined $NVDataCACHE{$_}{'value'} || length $NVDataCACHE{$_}{'value'} <= $MAX_VALUE_LENGTH }
                      keys %NVDataCACHE
                }
            ),
            0640
        );
    }
    catch {
        my $err = $_;
        if ( try { $err->get('error') == _EDQUOT } ) {

            # Logger it but do not throw into the UI
            Cpanel::Debug::log_warn( "Failed to save cache file “$cachefile” because of an error: " . Cpanel::Exception::get_string($err) );
        }
        else {
            warn "Failed to save cache file “$cachefile” because of an error: " . Cpanel::Exception::get_string($err);
        }
    };

    if ( $Cpanel::Debug::level > 3 ) {
        print STDERR __PACKAGE__ . "::_savecache\n";
    }
    return;
}

sub _dircheck {
    my $cpaneldir = getcpaneldir();
    my $nvdir     = $cpaneldir . '/nvdata';

    foreach my $dir ( $cpaneldir, $nvdir ) {
        if ( -e $dir && !-r _ ) { rename( $dir, $dir . '_unreadable' ); }
        if ( !-e $dir )         { mkdir( $dir, 0700 ); }
    }
    return ( $cpaneldir, $nvdir );
}

## DEPRECATED!
## note: this does *not* _execute Cpanel/API/NVData/get, as the UAPI version omits the
##   encoding functionality (considering encoding to be a responsibility of the caller)
sub api2_get {
    my %CFG     = @_;
    my @NAMES   = split( /\|/, $CFG{'names'} );
    my $default = $CFG{'default'};

    my @RSD;
    foreach my $name (@NAMES) {
        my $fetchname = $name;
        if ( $Cpanel::appname eq 'webmail' ) { $fetchname = $Cpanel::authuser . '_' . $name; }
        my $val = _get($fetchname);
        if ( !length $val && length $default ) { $val = $default; }
        if ( $CFG{'html_encode'} ) {
            push( @RSD, { 'name' => $name, 'value' => Cpanel::Encoder::Tiny::safe_html_encode_str($val) } );
        }
        elsif ( $CFG{'encoded'} ) {
            push( @RSD, { 'name' => $name, 'value' => Cpanel::Encoder::Tiny::safe_xml_encode_str($val) } );
        }
        else {
            push( @RSD, { 'name' => $name, 'value' => $val } );
        }
    }
    return (@RSD);
}

sub api2_set {
    my %CFG   = @_;
    my @NAMES = split( /\|/, $CFG{'names'} );
    my (@RSD);
    foreach my $name (@NAMES) {
        next if ( !exists $CFG{'setmissing'} && !defined $CFG{$name} && !defined( $Cpanel::FORM{$name} ) );
        my $setname = $name;
        if ( $Cpanel::appname eq 'webmail' ) { $setname = $Cpanel::authuser . '_' . $name; }
        _set( $setname, ( $CFG{$name} || $Cpanel::FORM{$name} || '' ), $CFG{'__nvdata::nocache'} ? 1 : 0 );
        push( @RSD, { set => $name } );
    }
    return (@RSD);
}

sub api2_setall {
    my (@RSD);
    foreach my $name ( keys %Cpanel::FORM ) {
        _set( $name, $Cpanel::FORM{$name}, 1 );
        push( @RSD, { set => $name } );
    }
    _savecache();
    return (@RSD);
}

sub _loadcache {
    my $save_cache_if_missing = shift;

    my $cachefile = getcpaneldir() . '/nvdata.cache';

    if ( open( my $cache_fh, '<', $cachefile ) ) {
        my $nvcache_ref;
        eval {
            local $SIG{'__DIE__'};               # Suppress spewage as we may be reading an invalid cache
            local $SIG{'__WARN__'} = sub { };    # and since failure is ok to throw it away
            $nvcache_ref = Cpanel::AdminBin::Serializer::LoadFile($cache_fh);
        };
        if ( $nvcache_ref && ( ref($nvcache_ref) eq 'HASH' ) ) {
            @NVDataCACHE{ keys %$nvcache_ref } = values %$nvcache_ref;
            $Cpanel::Debug::level > 3 && print STDERR __PACKAGE__ . "::_loadcache cache loaded from $cachefile\n";
            $NVCacheLoaded = 1;
            return;
        }
        close($cache_fh);
    }

    if ( $Cpanel::Debug::level > 3 ) {
        print STDERR __PACKAGE__ . "::_loadcache generating missing cache\n";
    }

    my $nvdir = getcpaneldir() . '/nvdata';
    if ( opendir( my $nv_dh, $nvdir ) ) {
        my @FHS = readdir($nv_dh);
        closedir($nv_dh);
        foreach my $file (@FHS) {
            next if ( $file =~ /^\.*$/ );

            my $file_mtime = Cpanel::StatCache::cachedmtime( $nvdir . '/' . $file );
            if ($file_mtime) {
                $NVDataCACHE{$file}{'mtime'} = $file_mtime;

                #NB: This will die() if the load fails.
                $NVDataCACHE{$file}{'value'} = Cpanel::LoadFile::load( $nvdir . '/' . $file );
            }
        }
    }

    _savecache() if $save_cache_if_missing;
    $NVCacheLoaded = 1;
    return;
}

=head1 _get(NAME)

Protected implementation used to fetch a single name/value pair from
the backing file location.  The method was designed to bypass api1
and api2 specific handling that is not needed for newer api calls.

=head2 Arguments

=over

=item NAME

String - the key name to store the value under. This is used to build the
file name in /home/<user>/.cpanel/nvdata/<name>.

=back

=head2 Returns

List with the following elements

(ERROR, PATH)

=over

=item ERROR

String - when its not empty, indicates the set failed.

=item PATH

String - full path to the output file if there is an error.

=back

=cut

sub _get {
    my ( $unsafename, $mtime, $size ) = @_;

    my $name = exists $GET_SAFE_NAME_CACHE{$unsafename} ? $GET_SAFE_NAME_CACHE{$unsafename} : ( $GET_SAFE_NAME_CACHE{$unsafename} = Cpanel::Encoder::Tiny::safe_xml_encode_str($unsafename) );

    $name = _sanitize_name_if_needed($name);

    my $nvdir = getnvdir();
    if ( !$mtime || !$size ) {
        ( $mtime, $size ) = Cpanel::StatCache::cachedmtime_size( $nvdir . '/' . $name );
    }
    if ( exists $NVDataCACHE{$name} && $NVDataCACHE{$name}{'mtime'} >= $mtime && _validate_name_is_valid( $name, $NVDataCACHE{$name}{'value'} ) ) {
        $Cpanel::Debug::level > 3 && print STDERR __PACKAGE__ . "::_get memory cache hit for name[$name] mtime[$mtime] cachemtime[$NVDataCACHE{$name}{'mtime'}]\n";
        return $NVDataCACHE{$name}{'value'};
    }
    else {
        $Cpanel::Debug::level > 3 && print STDERR __PACKAGE__ . "::_get memory cache miss for name[$name] mtime[$mtime] cachemtime[$NVDataCACHE{$name}{'mtime'}]\n";

        #NOTE: This will *write* the cache file.
        _loadcache(1) if !$NVCacheLoaded;

        if ( exists $NVDataCACHE{$name}{'mtime'} && $NVDataCACHE{$name}{'mtime'} >= $mtime && _validate_name_is_valid( $name, $NVDataCACHE{$name}{'value'} ) ) {
            $Cpanel::Debug::level > 3 && print STDERR __PACKAGE__ . "::_get disk cache hit for name[$name] mtime[$mtime] cachemtime[$NVDataCACHE{$name}{'mtime'}]\n";
            return $NVDataCACHE{$name}{'value'};
        }
        $Cpanel::Debug::level > 3 && print STDERR __PACKAGE__ . "::_get disk cache miss for name[$name] mtime[$mtime] cachemtime[$NVDataCACHE{$name}{'mtime'}]\n";

        #NB: This will die() if the load fails.
        my $value = ( $mtime && $size ) ? Cpanel::LoadFile::load("$nvdir/$name") : undef;

        $value = _validate_name_is_valid( $name, $value ) ? $value : undef;

        @{ $NVDataCACHE{$name} }{ 'value', 'mtime' } = ( $value, $mtime );
        return $value;
    }
}

sub _validate_name_is_valid {
    my ( $name, $value ) = @_;

    return 1 unless defined $value;

    # We are only interested in validating this if the name is defaultdir at this time
    # since file manager uses to determine its default starting cwd
    return 1 unless $name eq 'defaultdir';

    my $homedir = gethomedir();

    # If it is an absolute path, then we need to make sure it is
    # pinned to the user's homedir
    if ( $value =~ m{^/} && $value !~ m{^\Q$homedir\E} ) {
        warn "$name has been rejected since it is an absolute path outside the user’s homedir";
        return 0;
    }

    return 1;
}

sub NVData_fetch {
    my ( $name, $default, $isvar ) = @_;

    my $var = _get($name);
    $var =~ s/\n*$//g;
    if ( $var eq "" ) { $var = $default; }
    if ($isvar) {
        return $var;
    }
    else {
        print $var;
    }
    return;
}

sub NVData_fetchinc {    ## no critic (RequireFinalReturn)
    my ( $name, $default ) = @_;

    if ( $Cpanel::CPDATA{'DEMO'} eq "1" ) {
        print "Sorry, this feature is disabled in demo mode.";
        return;
    }

    my $var = _get($name);
    $var =~ s/\n*$//g;
    if ( $var eq "" ) { $var = $default; }
    main::doinclude("${var}.html");
}

sub NVData_brandingimage {
    my ( $image, $name, $default, $isvar ) = @_;

    my $post = NVData_fetch( $name, $default, 1 );

    require Cpanel::Branding;

    if ($isvar) {
        return Cpanel::Branding::Branding_image( "${image}${post}", 1 );
    }
    else {
        Cpanel::Branding::Branding_image("${image}${post}");
    }
    return;
}

my $allow_demo = { allow_demo => 1 };

our %API = (
    setall => $allow_demo,
    set    => $allow_demo,
    get    => $allow_demo,
);

sub api2 {
    my ($func) = @_;
    return { %{ $API{$func} } } if $API{$func};
    return;
}

1;
