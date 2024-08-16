package Whostmgr::Transfers::Locations;

# cpanel - Whostmgr/Transfers/Locations.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::PwCache::Build          ();
use Cpanel::Config::LoadWwwAcctConf ();
use Cpanel::Filesys::Mounts         ();
use Cpanel::Locale                  ();
use Cpanel::Validate::Username      ();
use Cpanel::FileUtils::Path         ();

my $valid_suffix_regex   = q{\.(?:tar|tgz|tar\.bz2|tar\.gz2|tar\.gz)$};
my $invalid_suffix_regex = q{\.zip(?:\.|$)};

#Made global for testing.
our @_DEFAULT_LOCATIONS = qw(
  /home
  /home2
  /home3
  /root
  /usr
  /usr/home
  /web
);

my $locale;

sub _locale {
    return $locale ||= Cpanel::Locale->get_handle();
}

#
sub get_quickrestore_files {
    my ($wanted_user) = @_;

    my @matched_files;
    my $pwcache_ref = Cpanel::PwCache::Build::fetch_pwcache();
    my %HOMES       = map { $_->[7] => 1 } @$pwcache_ref;

    foreach my $possible_location ( get_possiblelocs() ) {
        next if !-d $possible_location;

        opendir( my $pdr, $possible_location ) or do {
            return ( 0, _locale()->maketext( 'The system failed to open the directory “[_1]” because of an error: [_2]', $possible_location, $! ) );
        };

        while ( my $file = readdir $pdr ) {
            next if $file =~ m{^\.};
            next if $HOMES{"$possible_location/$file"};    # Ignore users homedirs
            if ( my $username = match_quickrestore_path("$possible_location/$file") ) {
                if ( $wanted_user && $username ne $wanted_user ) { next; }

                push @matched_files, {
                    'path' => $possible_location,    # legacy name
                    'file' => $file,
                    'user' => $username,
                };
            }
        }

        closedir $pdr or do {
            warn _locale()->maketext( 'The system failed to close the directory “[_1]” because of an error: [_2]', $possible_location, $! );
        };
    }

    return ( 1, \@matched_files );
}

sub get_possiblelocs {
    ## Using a hash to avoid duplication
    my %POSSIBLELOCS = map { $_ => 1 } ( @_DEFAULT_LOCATIONS, _get_additional_home_dirs() );

    ## Placing in alphanumeric order (note: /home will be first in most cases, which is good)
    my @locations = sort keys %POSSIBLELOCS;

    return @locations;
}

sub _get_additional_home_dirs {
    my @ADDITIONAL_HOME_DIRS;

    #Adds your homedir
    my $wwwacct_ref = Cpanel::Config::LoadWwwAcctConf::loadwwwacctconf();
    if ( exists $wwwacct_ref->{'HOMEDIR'} ) {
        push( @ADDITIONAL_HOME_DIRS, $wwwacct_ref->{'HOMEDIR'} );
    }

    #Also checks to see if any mounts match
    if ( exists $wwwacct_ref->{'HOMEMATCH'} ) {
        my $homematch = $wwwacct_ref->{'HOMEMATCH'};
        my %_mnts     = Cpanel::Filesys::Mounts::get_disk_mounts(0);
        my @_mnts     = values %_mnts;

        my @mnts_matching = grep( m/$homematch/, @_mnts );
        push( @ADDITIONAL_HOME_DIRS, @mnts_matching );
    }

    return @ADDITIONAL_HOME_DIRS;
}

#If a $user is passed in:
#   - Verifies that the filename matches the username.
#Otherwise:
#   - Verifies that the filename is a valid cpmove backup filename.
#
#Returns:
#   - If no match, an empty list.
#   - If match:
#       - the base of the filename (i.e., before the extension)
#       - either '.gz' or q<>, to indicate whether the file's extension indicates a gzipped archive
#       - either '.tar' or q<>, to indicate ^^ (but for tar)
#       - the username
#
sub match_quickrestore_path {
    my ( $path, $wanted_user ) = @_;

    my ( $dir, $file ) = Cpanel::FileUtils::Path::dir_and_file_from_path($path);

    my $is_dir          = -d $path;
    my $is_regular_file = -f _;

    # Eliminate anything that cannot possibly be a cpmove archive
    if ($is_dir) {
        return if !-d "$path/cp";
    }
    elsif ($is_regular_file) {
        return if $file !~ m{$valid_suffix_regex} || $file =~ m{$invalid_suffix_regex};
    }
    else {
        return;
    }

    return match_quickrestore_filename( $file, $wanted_user );
}

sub match_quickrestore_filename {
    my ( $test_file, $wanted_user ) = @_;

    my $username_validator_regex_str = Cpanel::Validate::Username::get_system_username_regexp_str();
    $username_validator_regex_str =~ s{^\^}{};
    $username_validator_regex_str =~ s{\$$}{};

    # This is a tarball of some software package
    if ( $test_file !~ m{^(?:cp)?backup} && $test_file =~ m{-[0-9]+\.[0-9]+.*?$valid_suffix_regex} ) {
        return;
    }

    # We cannot handle .zip files
    elsif ( $test_file =~ m{$invalid_suffix_regex} ) {
        return;
    }

    $test_file =~ s{$valid_suffix_regex}{};

    # Now reject by filename
    my $username;
    if ( $test_file =~ m{^cpmove[^-]*-} ) {
        if ( $test_file =~ m{^cpmove[^-]*-($username_validator_regex_str)} ) {
            $username = $1;
        }
    }
    elsif ( $test_file =~ m{^(?:cp)?backup[^-]*-} ) {
        if ( $test_file =~ m{^(?:cp)?backup[^-]*-\d+[.]\d+[.]\d+_\d+\-\d+\-\d+_($username_validator_regex_str)} ) {
            $username = $1;
        }
    }
    elsif ( $test_file =~ m{^($username_validator_regex_str)\.[0-9]+$} ) {
        $username = $1;
    }
    elsif ( $test_file !~ m{\s} && $test_file =~ m{($username_validator_regex_str)} ) {
        $username = $1;
    }

    # Strip " (1).tar.gz"
    $username =~ s/[ \t]+.*?$//g if length $username;

    if ( !length $username ) {
        return;
    }
    elsif ( length $wanted_user && $username ne $wanted_user ) {
        return;
    }

    return $username;
}

1;
