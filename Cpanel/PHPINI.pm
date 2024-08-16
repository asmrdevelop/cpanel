package Cpanel::PHPINI;

# cpanel - Cpanel/PHPINI.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::SafeFile                     ();
use Cpanel::CachedDataStore              ();
use Cpanel::SafeDir::MK                  ();
use Cpanel::SafeDir::Read                ();
use Cpanel::SafeRun::Simple              ();
use Cpanel::Transaction::File::RawReader ();
use Cpanel::Version::Compare             ();
use Cpanel::CachedCommand                ();
use Cpanel::Imports;

our $DIRECTIVES_YAML                  = '/usr/local/cpanel/whostmgr/etc/phpini_directives.yaml';
our $ADDITIONAL_PHPINI_DIRECTIVES_DIR = '/etc/cpanel/ea4/phpini_directives';

my $default_php_prefix = '/usr/local';

sub PHPINI_init { return 1; }

sub _check_php_prefix {
    my ($php_prefix) = @_;

    if ( !$php_prefix ) {
        $php_prefix = $default_php_prefix;
    }
    if ( !-d $php_prefix ) {
        logger->warn("Improper PHP installation prefix $php_prefix. Not a directory, check your installation.");
        return;
    }
    return $php_prefix;
}

sub _get_php_ini_in_dir {
    my ($dir) = @_;
    return if !$dir;

    if ( -e $dir . '/lib/php.ini' ) {
        return $dir . '/lib/php.ini';
    }
    elsif ( -e $dir . '/php.ini' ) {
        return $dir . '/php.ini';
    }
    elsif ( -e $dir . '/etc/php.ini' ) {
        return $dir . '/etc/php.ini';
    }
    return;
}

sub check_installed_php_binaries {
    my $installed_phps = {
        'D' => { 'prefix' => '/usr/local',      'path' => '/usr/bin/php',      'version' => 0, 'sapi' => 'none' },
        'A' => { 'prefix' => '/usr/local/php4', 'path' => '/usr/php4/bin/php', 'version' => 0, 'sapi' => 'none' },
    };
    local %ENV = ();
    foreach my $phpinstall ( 'D', 'A' ) {
        if ( !-x $installed_phps->{$phpinstall}->{'path'} ) {
            if ( $installed_phps->{$phpinstall}->{'path'} eq '/usr/bin/php' ) {
                $installed_phps->{$phpinstall}->{'path'} = '/usr/local/bin/php';
                redo;
            }
            next;
        }

        my $php_info = _get_php_info_from_binary( $installed_phps->{$phpinstall}->{'path'} );

        if ( exists $php_info->{'error'} ) {
            {
                my $cplog_func = ref( logger() ) . "::cplog";
                no strict "refs";
                $cplog_func->( $php_info->{'error'}, 'warn', __PACKAGE__, 1 );
            }
            if ( $installed_phps->{$phpinstall}->{'path'} eq '/usr/bin/php' ) {
                $installed_phps->{$phpinstall}->{'path'} = '/usr/local/bin/php';
                redo;
            }
            next;
        }
        $installed_phps->{$phpinstall}->{'long_version'} = $php_info->{'long_version'};
        $installed_phps->{$phpinstall}->{'version'}      = $php_info->{'version'};
        $installed_phps->{$phpinstall}->{'sapi'}         = $php_info->{'sapi'};

    }
    return $installed_phps;
}

# Return some basic information on the php binary
# Information return: version  (5), long_version (5.0.0) and sapi (dso/cgi/etc).
sub _get_php_info_from_binary {
    my ($php_binary_path) = @_;

    if ( !-x $php_binary_path ) {
        return { 'error' => "php binary ${php_binary_path} is not executable" };
    }

    my $phpout = Cpanel::CachedCommand::cachedcommand( $php_binary_path, '-n', '-v' );
    my $status = $?;

    my $php_info = {};

    if ( $phpout =~ m/^PHP\s+(\d+\.\d+\.\d+)\s+\(([^\)]+)\)/m ) {
        $php_info->{'long_version'} = $1;
        ( $php_info->{'version'} ) = split( /\./, $php_info->{'long_version'} );
        $php_info->{'sapi'} = $2;
    }
    else {
        my $msg;
        if ( $status != 0 ) {
            $msg .= sprintf( "PHP process exited nonzero (%s).\n", $status >> 8 );
        }
        $msg .= 'Unexpected output from ' . $php_binary_path . ' -v : ' . $phpout;
        chomp( $php_info->{'error'} = $msg );
    }
    return $php_info;
}

sub include_paths {    ## no critic qw(Subroutines::RequireArgUnpacking)
    my $php_prefix = _check_php_prefix(@_);
    return if !$php_prefix;

    my $php_ini = _get_php_ini_in_dir($php_prefix);
    if ( !$php_ini ) {
        logger->warn("Unable to locate php.ini in directory $php_prefix");
        return;
    }

    my $phplock = Cpanel::SafeFile::safeopen( \*PHPINI, '<', $php_ini );
    if ($phplock) {
        my $include_path;
        while ( my $line = <PHPINI> ) {
            if ( $line =~ m/^\s*include_path\s*=/ ) {
                chomp $line;
                $line =~ s/\s*;.*$//g;    # Trim EOL comments
                my $paths = ( split( /\s*=\s*/, $line ) )[1];
                $paths =~ s/\s//g;        # Remove spaces in path
                $paths =~ s/\"//g;
                $include_path = $paths;
            }
        }
        Cpanel::SafeFile::safeclose( \*PHPINI, $phplock );
        my @paths;
        @paths = split( /:/, $include_path ) if defined $include_path;
        return wantarray ? @paths : \@paths;
    }
    else {
        logger->warn("Unable to open $php_prefix/lib/php.ini: $!");
        return;
    }
}

sub installed_extensions {    ## no critic qw(Subroutines::RequireArgUnpacking)
    my $php_prefix = _check_php_prefix(@_);
    return if !$php_prefix;

    my $php_ini = _get_php_ini_in_dir($php_prefix);
    if ( !$php_ini ) {
        logger->warn("Unable to locate php.ini in directory $php_prefix");
        return;
    }

    my $txn     = Cpanel::Transaction::File::RawReader->new( path => $php_ini );
    my $data_sr = $txn->get_data;
    unless ( defined $$data_sr ) {
        logger->warn("Unable to read $php_ini: $!");
        return;
    }
    return map {
        my ( undef, $value ) = split /\s*=\s*/, $_;
        $value =~ s/[\s"]//gr
    } map { s/\s*;.*$//gr } grep { m/^\s*extension\s*=/ } split /\n/, $$data_sr;
}

sub uninstall_extension {
    my ( $ext, $php_prefix ) = @_;
    if ( !$ext ) {
        logger->warn('No extension specified to uninstall');
        return wantarray ? ( 0, 'You must specify an extension to uninstall' ) : undef;
    }

    $php_prefix = _check_php_prefix($php_prefix);
    return if !$php_prefix;

    my $php_ini = _get_php_ini_in_dir($php_prefix);
    if ( !$php_ini ) {
        logger->warn("Unable to locate php.ini in directory $php_prefix");
        return wantarray ? ( 0, "Unable to locate php.ini in directory $php_prefix" ) : undef;
    }

    if ( !-e $php_ini ) {
        logger->warn("php.ini \"$php_ini\" not found");
        return ( 0, '' );
    }
    my $phplock = Cpanel::SafeFile::safeopen( \*PHPINI, '+<', $php_ini );
    if ($phplock) {
        my $installed = 0;
        my @PHPINI;
        while ( my $line = <PHPINI> ) {
            if ( $line =~ m/^\s*extension\s*=/ ) {
                my $directive_line = $line;
                chomp $directive_line;
                $directive_line =~ s/;.*$//g;
                my $value = ( split( /\s*=\s*/, $directive_line ) )[1];
                $value =~ s/\s//g;
                $value =~ s/\"//g;
                if ( $value eq $ext ) {
                    $installed = 1;
                    next;
                }
            }
            push @PHPINI, $line;
        }
        if ( !$installed ) {
            Cpanel::SafeFile::safeclose( \*PHPINI, $phplock );
            return ( 1, "extension $ext uninstalled in $php_ini" );
        }
        else {
            seek( PHPINI, 0, 0 );
            print PHPINI join( '', @PHPINI );
            truncate( PHPINI, tell(PHPINI) );
            Cpanel::SafeFile::safeclose( \*PHPINI, $phplock );

            return ( 1, "extension $ext was uninstalled in $php_ini" );
        }
    }
    else {
        logger->warn("Unable to read $php_ini: $!");
        return;
    }
}

sub install_extension {
    my ( $ext, $php_prefix ) = @_;
    if ( !$ext ) {
        logger->warn('No extension specified to install');
        return wantarray ? ( 0, 'You must specify an extension to uninstall' ) : undef;
    }

    $php_prefix = _check_php_prefix($php_prefix);
    return if !$php_prefix;

    my $php_ini = _get_php_ini_in_dir($php_prefix);
    if ( !$php_ini ) {
        logger->warn("Unable to locate php.ini in directory $php_prefix");
        return wantarray ? ( 0, "Unable to locate php.ini in directory $php_prefix" ) : undef;
    }

    # Check if extension is valid
    my $extension_dir = get_extension_dir($php_prefix);
    if ( !defined $extension_dir || !-e "$extension_dir/$ext" ) {
        my $default_extension_dir = get_default_extension_dir($php_prefix);
        if ( !defined $default_extension_dir || !-e "$default_extension_dir/$ext" ) {
            return ( 0, "The $ext object is not in " . ( $extension_dir // "" ) );
        }
        else {
            set_extension_dir($php_prefix);
        }
    }

    if ( !-e $php_ini ) {
        logger->warn("php.ini \"$php_ini\" not found");
        return ( 0, '' );
    }
    my $phplock = Cpanel::SafeFile::safeopen( \*PHPINI, '+<', $php_ini );
    if ($phplock) {
        my $installed    = 0;
        my $ext_dir_line = 0;
        my $line_count   = 0;
        my @PHPINI;
        while ( my $line = <PHPINI> ) {
            $line_count++;
            if ( $line =~ m/^\s*extension_dir\s*=/ ) {
                $ext_dir_line = $line_count;
            }
            elsif ( $line =~ m/^\s*extension\s*=/ ) {
                my $extension_line = $line;
                chomp $extension_line;
                if ( !$ext_dir_line ) { $ext_dir_line = $line_count; }

                $extension_line =~ s/;.*$//g;
                my $value = ( split( /\s*=\s*/, $extension_line ) )[1];
                $value =~ s/\"//g;
                $value =~ s/\s//g;
                if ( $value eq $ext ) {
                    $installed = 1;
                }
            }
            push @PHPINI, $line;
        }
        if ($installed) {
            Cpanel::SafeFile::safeclose( \*PHPINI, $phplock );
            return ( 1, "extension $ext installed in $php_ini" );
        }
        else {

            # Add after extension_dir
            splice( @PHPINI, $ext_dir_line, 0, "extension=$ext\n" );

            seek( PHPINI, 0, 0 );
            print PHPINI join( '', @PHPINI );
            truncate( PHPINI, tell(PHPINI) );
            Cpanel::SafeFile::safeclose( \*PHPINI, $phplock );

            return ( 1, "extension $ext was installed in $php_ini" );
        }
    }
    else {
        logger->warn("Unable to open $php_ini for read/write: $!");
        return wantarray ? ( 0, "Unable to update $php_ini" ) : undef;
    }
}

sub get_extension_dir {
    my ($php_prefix) = @_;
    $php_prefix = _check_php_prefix($php_prefix);
    return if !$php_prefix;

    my $path = get_directive( 'extension_dir', $php_prefix );
    if ( !$path || $path eq './' || $path eq '/' || $path eq '.' ) {

        #  this seems to break improperly installed ioncube
        set_extension_dir($php_prefix);
        $path = get_default_extension_dir($php_prefix);
    }
    my $ext_dir = ( !defined $path || $path ne './' ) ? $path : get_default_extension_dir($php_prefix);
    if ( defined $ext_dir && !-e $ext_dir ) {
        Cpanel::SafeDir::MK::safemkdir( $ext_dir, '0755' );
    }
    return $ext_dir;
}

my $webserver_role_allow_demo = { needs_role => "WebServer", allow_demo => 1 };

our %API = (
    getoptions    => $webserver_role_allow_demo,
    getalloptions => $webserver_role_allow_demo,
);

sub api2 {
    my ($func) = @_;
    return { %{ $API{$func} } } if $API{$func};
    return;
}

sub api2_getalloptions {
    my %OPTS       = @_;
    my $php_prefix = _check_php_prefix( $OPTS{'php_prefix'} );
    return if !$php_prefix;

    my @RSD;
    my @DIRLIST;
    my $rCONF = get_configurable($php_prefix);
    if ( defined $OPTS{'dirlist'} ) {
        @DIRLIST = sort split( /\|/, $OPTS{'dirlist'} || '' );
    }
    else {
        foreach my $dir ( keys %{ $rCONF->{'dirs'} } ) {
            push @DIRLIST, $dir;
        }
    }

    my $getnull = 1;
    if ( defined $OPTS{'getnull'} ) {
        $getnull = $OPTS{'getnull'} ? 1 : 0;
    }

    my $dirref = get_directives( \@DIRLIST, $getnull, $php_prefix );

    my %SECS;
    foreach my $opt (@DIRLIST) {
        my $info = '';
        if ( ref $rCONF->{'dirs'}{$opt}{'info'} eq 'SCALAR' ) {
            $info = ${ $rCONF->{'dirs'}{$opt}{'info'} };
        }
        my $cfg = $dirref->{$opt};
        next unless defined $cfg;

        my $section = $rCONF->{'dirs'}{$opt}{'section'};
        next unless $section;
        $SECS{$section} ||= [];

        my $commented;
        my $values;

        # directives with multiple values are stored in an arrayref
        if ( ref $cfg eq 'HASH' ) {
            $commented = $cfg->{'commented'};
            $values    = [ $cfg->{'value'} ];
        }
        elsif ( ref $cfg eq 'ARRAY' ) {
            $commented = 0;
            $values    = $cfg;
        }
        else {
            next;
        }

        foreach my $value (@$values) {
            push @{ $SECS{$section} },
              {
                'directive'  => $opt,
                'value'      => $value,
                'commented'  => $commented,
                'info'       => $info,
                'section'    => $rCONF->{'dirs'}{$opt}{'section'},
                'subsection' => $rCONF->{'dirs'}{$opt}{'subsection'}
              };
        }
    }
    foreach my $sec ( sort keys %SECS ) {
        push( @RSD, { 'section' => $sec, 'dirlist' => $SECS{$sec} } );
    }
    return \@RSD;
}

sub api2_getoptions {
    my %OPTS = @_;

    # make sure that these two options are defined
    $OPTS{'dirlist'} ||= '';
    $OPTS{'getnull'} ||= 0;

    # we should be able to return directly that answer
    #   but we need to rename 'value' as 'dirvalue' before
    my $options = api2_getalloptions(%OPTS);
    return unless $options;

    my @RSD;

    foreach my $section (@$options) {
        foreach my $opt ( @{ $section->{dirlist} } ) {
            $opt->{'dirvalue'} = $opt->{'value'};
            delete $opt->{'value'};
            push @RSD, $opt;
        }
    }

    return \@RSD;
}

sub get_configurable {    ## no critic qw(Subroutines::RequireArgUnpacking)
    my $php_prefix = _check_php_prefix(@_);
    return if !$php_prefix;

    my $php_ini = _get_php_ini_in_dir($php_prefix);
    if ( !$php_ini ) {
        logger->warn("Unable to locate php.ini in directory $php_prefix");
        return;
    }

    my $phplock = Cpanel::SafeFile::safeopen( \*PHPINI, '<', $php_ini );
    if ( !$phplock ) {
        logger->warn("Could not read from $php_ini");
        return ( '', '' );
    }
    my $info   = '';
    my $presec = 0;
    my $msec   = 0;
    my $section;
    my $subsection;
    my %DIRLIST;
    my %DIRS;

    my $directives_ref = get_directives_from_filesys();

    while (<PHPINI>) {
        if ( /^\s*\;\;\;\;\;\;\;\;\;\;\;/ || /\s*\;\s*End:/ || /^\s*\;\s*$/ ) {
            if (/^\s*\;\;\;\;\;\;\;\;\;\;\;/) {
                if ( $presec == 1 ) {
                    $presec     = 0;
                    $subsection = $msec;
                }
                else {
                    $presec = 1;
                }
            }
            else {
                $presec = 0;
            }
            $info = '';
        }
        elsif (/^\s*\;*\s*(\S+)\s*=[^>]/) {
            my $directive = $1;
            if ( !exists $directives_ref->{$directive} ) {
                logger->info("Skipping unknown PHP ini directive $directive");
                next;
            }
            s/^\s*\;*//g;
            if (/\;+(.*)$/) {
                $info .= $1;
            }
            $info =~ s/^\s*|\s*$//g;
            my $dirinfo = $info;
            push @{ $DIRLIST{$section}{$subsection} },
              {
                'directive' => $directive,
                'info'      => \$dirinfo
              };
            $DIRS{$directive} = {
                'section'    => $section,
                'subsection' => $subsection,
                'info'       => \$dirinfo
            };
            $info = '';
        }
        elsif (/^\s*\[([^\]]+)\]/) {
            $section    = $1;
            $subsection = 'main';
        }
        elsif (/^\s*;*/) {
            if ( $presec == 1 && /^\s*\;*\s*([^\;]+)/ ) {
                $msec = $1;
                $msec =~ s/\s*$//;
            }
            s/^\s*\;//g;
            $info .= $_;
        }
    }
    Cpanel::SafeFile::safeclose( \*PHPINI, $phplock );
    return ( { 'dirtree' => \%DIRLIST, 'dirs' => \%DIRS } );
}

sub get_directive {
    my ( $directive, $php_prefix ) = @_;
    return if !$directive;

    $php_prefix = _check_php_prefix($php_prefix);
    return if !$php_prefix;

    my $dirref = get_directives( [$directive], 0, $php_prefix );

    my $cfg = $dirref->{$directive};
    return unless $cfg;

    return $cfg->{'value'} if ref $cfg eq 'HASH';

    # handle multiple directive
    return join( ',', @$cfg ) if ref $cfg eq 'ARRAY';
    return;
}

# Determine if a directive is supported by a specific version of php.
#   $php_version  - the version of PHP we are checking against
#   $directive    - the name of the directive (passed in for debugging purposes)
#   $directive_hr - the directive hashref as per the phpini_directives.yaml file (and the “additional PHP INI directives” system)
sub directive_supported {
    my ( $php_version, $directive, $directive_hr ) = @_;

    if ( exists $directive_hr->{'deprecated'} ) {
        if ( Cpanel::Version::Compare::compare( $php_version, '>=', $directive_hr->{'deprecated'} ) ) {
            return 0;
        }
    }

    if ( exists $directive_hr->{'added'} ) {
        if ( Cpanel::Version::Compare::compare( $php_version, '<', $directive_hr->{'added'} ) ) {
            return 0;
        }
    }
    return 1;
}

sub get_directives_from_filesys {
    my $directives_ref = Cpanel::CachedDataStore::fetch_ref($DIRECTIVES_YAML);

    # the “additional PHP INI directives” system:
    if ( -d $ADDITIONAL_PHPINI_DIRECTIVES_DIR ) {
        my @files = sort( Cpanel::SafeDir::Read::read_dir($ADDITIONAL_PHPINI_DIRECTIVES_DIR) );
        for my $name (@files) {
            my $file = "$ADDITIONAL_PHPINI_DIRECTIVES_DIR/$name";
            if ( -f $file && -s _ ) {
                next if ( $file =~ m{\.cache$} );
                if ( $file !~ m/\.yaml$/ ) {
                    logger->info("$file does not end in .yaml");
                    next;
                }

                my $hr = Cpanel::CachedDataStore::fetch_ref($file);    # this warns about any issues loading it
                if ( !$hr || !exists $hr->{directives} || !keys %{ $hr->{directives} } ) {
                    logger->info("$file contains no INI directives");
                    next;
                }

                for my $directive ( keys %{ $hr->{directives} } ) {
                    if ( exists $directives_ref->{$directive} ) {
                        logger->info("Directive “$directive” already exists in directive data, ignoring the version in $file.");
                        next;
                    }

                    $directives_ref->{$directive} = $hr->{directives}{$directive};
                }
            }
            else {
                logger->info("$file is not a YAML file, ignoring …");
            }
        }
    }

    return $directives_ref;
}

sub get_directives {
    my ( $dirsnref, $getnull, $php_prefix ) = @_;
    return if !defined $dirsnref;

    $php_prefix = _check_php_prefix($php_prefix);
    return if !$php_prefix;

    my $php_ini = _get_php_ini_in_dir($php_prefix);
    if ( !$php_ini ) {
        logger->warn("Unable to locate php.ini in directory $php_prefix");
        return;
    }

    my $directive_regex = '\S+';
    if ( ref $dirsnref eq 'ARRAY' ) {
        $directive_regex = join( '|', @{$dirsnref} );
    }

    my $directives_ref = get_directives_from_filesys();                           # Needed for multiple lookup
    my $phplock        = Cpanel::SafeFile::safeopen( \*PHPINI, '<', $php_ini );
    if ( !$phplock ) {
        logger->warn("Could not read from $php_ini");
        return (0);
    }
    my %dirs;
    while (<PHPINI>) {
        chomp;
        if ( m/^[;\s]*($directive_regex)\s*=/ && exists $directives_ref->{$1} ) {
            my $directive   = $1;
            my $iscommented = m/^\s*;/ ? 1 : 0;

            # Don't overwrite existing values with a commented one
            next if ( exists $dirs{$directive} && $iscommented );

            s/^[\;\s]*//g;    # remove leading comment char as the below line will nuke it

            my $var = ( split( /\s*=\s*/, $_, 2 ) )[1];

            if ( !defined $var ) { $var = ''; }

            $var =~ s/^\s*|\s*$//g;
            if ( $var =~ /^\"/ ) {

                #this is a hack because the regex is always too greedy
                # we want to take off  the quote and anything after from
                #      "bob;cow"
                #      but \".*$ will match the whole item from the start
                $var .= ' ;safesplit';
                my @SAFEVAR = split( /\"/, $var );
                pop(@SAFEVAR);    #strip trailing garbage
                if ( $SAFEVAR[0] =~ /^\s+$/ ) { shift(@SAFEVAR); }
                $var = join( '"', @SAFEVAR );
            }
            else {
                $var =~ s/;.*$//g;    # Strip trailing comments
            }

            # Cleanup value
            $var =~ s/^\"|\"$//g;

            if ( $getnull || $var ne '' ) {
                if ( $directives_ref->{$directive}{'multiple'} ) {
                    if ( !$iscommented ) {
                        push @{ $dirs{$directive} }, $var;
                    }
                }
                else {
                    $dirs{$directive} = { 'value' => $var, 'commented' => $iscommented };
                }
            }
        }
    }
    Cpanel::SafeFile::safeclose( \*PHPINI, $phplock );

    return \%dirs;
}

sub get_default_extension_dir {
    my $php_prefix = _check_php_prefix(@_);
    return if !$php_prefix;
    return if !-x $php_prefix . '/bin/php-config';
    my $ext_dir = Cpanel::SafeRun::Simple::saferun( $php_prefix . '/bin/php-config', '--extension-dir' );
    $ext_dir =~ s/[\r\n]//g;
    return $ext_dir;
}

sub _get_php_version_from_prefix {
    my ($php_prefix) = @_;

    my $php_info;

    if ( $php_prefix =~ /^\/usr\/local\/cpanel\/3rdparty\// ) {
        $php_prefix .= '/' if substr( $php_prefix, -1 ) ne '/';
        $php_info = _get_php_info_from_binary( $php_prefix . 'bin/php' );
        warn $php_info->{'error'} if $php_info->{'error'};
        return $php_info->{'long_version'};
    }

    $php_info = check_installed_php_binaries();
    foreach my $php_install ( values %{$php_info} ) {
        return $php_install->{'long_version'} if $php_install->{'prefix'} eq $php_prefix;
    }
    return undef;
}

sub set_directive {
    my ( $directive, $value, $php_prefix ) = @_;
    return if !$directive;
    $php_prefix = _check_php_prefix($php_prefix);
    return if !$php_prefix;
    return set_directives( { $directive => $value }, $php_prefix );
}

sub set_directives {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my ( $dirref, $php_prefix ) = @_;
    return if !defined $dirref;
    $php_prefix = _check_php_prefix($php_prefix);
    return if !$php_prefix;

    my $php_ini = _get_php_ini_in_dir($php_prefix);
    if ( !$php_ini ) {
        logger->warn("Unable to locate php.ini in directory $php_prefix");
        return;
    }

    my $php_version = _get_php_version_from_prefix($php_prefix);
    if ( !$php_version ) {
        logger->warn("Unable to determine php version for $php_prefix");
        return;
    }

    my $directives_ref     = get_directives_from_filesys();
    my $current_directives = get_directives( undef, 1, $php_prefix );

    # Validate memory_limit in user-entered form data.
    if ( exists $dirref->{memory_limit} ) {    # if field is present in form data...
        my $limit = $dirref->{memory_limit};
        if ( $limit =~ / ^ \s* (\d+) \s* MB? \s* $ /ix ) {    # validate ; drop lead/trail/embedded white
            $limit = "$1M";                                   # "B" is optional, but do not pass it thru
            $dirref->{memory_limit} = $limit;
        }
        else {

            # User entered bad value for memory_limit. If this
            # subrtn was called from a template, we'll display
            # an error to inform user about bad value and force
            # user to re-enter.
            return unless int $limit == -1;
        }
    }
    if ( scalar keys %{$dirref} ) {
        my $directive_list = join( '|', keys %{$dirref} );

        if ( !-e $php_ini ) {
            logger->warn("php.ini \"$php_ini\" not found");
            return ( 0, '' );
        }
        my $phplock = Cpanel::SafeFile::safeopen( \*PHPINI, '+<', $php_ini );
        if ( !$phplock ) {
            logger->warn("Could not edit $php_ini");
            return (0);
        }
        my %DIDDIRS;
        my %multi_strip;
        my @PHPINI;

      INI_LINE: while (<PHPINI>) {
            my $line = $_;
            my ($directive) = $line =~ m/^[;\s]*(\S+)\s*=/;

            if ( defined $directive && exists $dirref->{$directive} ) {

                next if ( exists $multi_strip{$directive} );

                if ( ( $DIDDIRS{$directive} && !$directives_ref->{$directive}{'multiple'} ) || ( /^\s*\;/ && ( !exists $dirref->{$directive} || $dirref->{$directive} eq '' ) ) ) {
                    if (m/^\s*;/) {
                        push @PHPINI, $_;
                    }
                    else {
                        push @PHPINI, ";$_";
                    }
                }
                else {
                    if ( $dirref->{$directive} eq '' ) {
                        push @PHPINI, "$directive =\n";
                        if ( $directives_ref->{$directive}{'multiple'} ) {
                            $multi_strip{$directive} = 1;
                        }
                    }
                    else {
                        my $value = $dirref->{$directive};
                        $value =~ s/^\s+//;
                        $value =~ s/\s+$//;
                        if ( $directives_ref->{$directive}{'multiple'} ) {
                            my @values = split( /\s*,\s*/, $value );
                            foreach my $val (@values) {
                                $val =~ s/^\s+//;    # Strip leading white  - Case 3102
                                $val =~ s/\s+$//;    # Strip trailing white - Case 3102
                                if ( $val =~ m/^(?:on|off)/i || $val =~ m/^\-?\d+/i || $val =~ /^E_/ ) {
                                    push @PHPINI, $directive . ' = ' . $val . "\n";
                                }
                                elsif ( $val =~ m/\s/ || $val =~ m/\W/ || $directive =~ m/_order$/ || $directive =~ m/_case$/ ) {
                                    push @PHPINI, $directive . ' = "' . $val . "\"\n";
                                }
                                else {
                                    push @PHPINI, $directive . ' = ' . $val . "\n";
                                }
                            }
                            $multi_strip{$directive} = 1;
                        }
                        elsif ( $value =~ m/^(?:on|off)/i || $value =~ m/^\-?\d+M?$/i || $value =~ m/^E_/ ) {
                            push @PHPINI, $directive . ' = ' . $value . "\n";
                        }
                        elsif ( $value =~ m/\s/ || $value =~ m/\W/ || $directive =~ m/_order$/ || $directive =~ m/_case$/ ) {

                            push @PHPINI, $directive . ' = "' . $value . '"' . "\n";
                        }
                        else {
                            push @PHPINI, $directive . ' = ' . $value . "\n";
                        }

                        $DIDDIRS{$directive} = 1;
                    }
                }
            }
            elsif ( $line !~ /^\s*;/ && defined($directive) && !directive_supported( $php_version, $directive, $directives_ref->{$directive} ) ) {
                chomp $line;
                push @PHPINI, ";$line ; deprecated\n";
            }
            else {
                push @PHPINI, $_;
            }
        }

        seek( PHPINI, 0, 0 );
        print PHPINI join( '', @PHPINI );
        truncate( PHPINI, tell(PHPINI) );
        Cpanel::SafeFile::safeclose( \*PHPINI, $phplock );
    }
    return 1;
}

sub set_extension_dir {
    my $php_prefix = _check_php_prefix(@_);
    return if !$php_prefix;

    my $default_ext_dir = get_default_extension_dir($php_prefix) || './';
    return set_directive( 'extension_dir', $default_ext_dir, $php_prefix );
}

1;
