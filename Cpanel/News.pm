package Cpanel::News;

# cpanel - Cpanel/News.pm                          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::PwCache  ();
use Cpanel::LoadFile ();

#
# method: get_base_news_dir
# returns: returns the base news directory.
#
sub get_base_news_dir {
    return '/var/cpanel/news';
}

#
# method: get_global_news_file
# returns: returns the global news file path.
#
sub get_global_news_file {
    return get_base_news_dir() . '/global-news';
}

#
# method: get_resold_news_file
# returns: returns the resold news file path.
#
sub get_resold_news_file {
    return get_base_news_dir() . '/global-resold';
}

#
# method: get_cpanel_news_file
#
# param: $owner - owner of the current $Cpanel::user.
# returns: returns the cpanel news file path from the current user's owner directory
#
sub get_cpanel_news_file {
    my ($owner) = @_;
    return get_base_news_dir() . "/$owner/news";
}

#
# method: get_owner
#
# returns: returns the owner of the current $Cpanel::user.
#
sub get_owner {
    my $owner = $Cpanel::CPDATA{'OWNER'} || 'root';
    $owner =~ s/\///g;
    return $owner;
}

#
# DEPRICATED - DO NOT USE IN NEW CODE
# method: displaynews
#   This method reads content from news files and prints them in cPanel home page
#   for X3 theme.
#
sub displaynews {
    _print_file('/var/cpanel/news/global-news');

    my $owner = get_owner();

    if ( $owner && $owner ne 'root' && ( $owner eq $Cpanel::user || ( Cpanel::PwCache::getpwnam($owner) )[0] ne '' ) ) {
        _print_file('/var/cpanel/news/global-resold');
    }
    _print_file("/var/cpanel/news/$owner/news");
}

#
# DEPRICATED - DO NOT USE IN NEW CODE
# method: _print_file
#   This method reads the content from the requested file and prints
#   it to STDOUT.
#
# param: $file - path to the specific news file.
#
sub _print_file {
    my $file = shift;
    return unless $file && -r $file;
    print Cpanel::LoadFile::loadfile($file);
}

#
# method: get_news
#   This method reads content from a given news file type.
#   Accepted values are:
#    > global
#    > resold
#    > cpanel
#
# param: $news_type- the news type value.
# returns: returns the data read from the file of given news type.
#
sub get_news {
    my %ARGS = @_;    # The argument always comes as a hash value. This is a consequence of using API2 structure.

    my $news_type = $ARGS{"type"};
    if ($news_type) {
        my $owner = get_owner();
        if ( $news_type eq "global" ) {
            return _get_news_content( get_global_news_file() );
        }
        elsif ( $news_type eq "resold" ) {
            if ( $owner && $owner ne 'root' && ( $owner eq $Cpanel::user || ( Cpanel::PwCache::getpwnam($owner) )[0] ne '' ) ) {
                return _get_news_content( get_resold_news_file() );
            }
        }
        elsif ( $news_type eq "cpanel" ) {
            return _get_news_content( get_cpanel_news_file($owner) );
        }
    }
}

#
# method: _get_news_content
#   This method reads content from a given news file.
#
# param: $file- news file path.
# returns: returns the data read from the file.
#
sub _get_news_content {
    my ($file) = @_;

    return unless $file && -r $file;
    my $newsData = Cpanel::LoadFile::loadfile($file);

    if ($newsData) {
        return $newsData;
    }
}

#
# method: does_news_exist
#   This is publicly available method which calls _does_any_news_type_exist method
#   to see if atleast one exists.
#
# returns: returns true if atleast one exists
#
sub does_news_exist {
    my $owner = get_owner();

    return _does_any_news_file_exist(
        get_global_news_file(),
        get_resold_news_file(),
        get_cpanel_news_file($owner)
    );
}

#
# method: _does_any_news_file_exist
#   This method loops through all news file paths passed in to see if at
#   least one exists on the file system.
#
# param: @news_file_list - list of file paths to check.
# returns: returns true if at least one of the files exists
#
sub _does_any_news_file_exist {
    my @news_file_list = @_;
    my $does_exist     = 0;
    foreach (@news_file_list) {
        $does_exist = _does_given_news_file_exist($_);
        if ($does_exist) {
            return $does_exist;
        }
    }
}

#
# method: does_news_file_exist
#   This method checks to see if a given news files exists.
#
# param: %ARGS - parameters passed to the API. We are only interested in the
#    the "type" element of the hash.  This method handles the following news
#    types:
#       * global - Global News,
#       * resold - Resold News,
#       * cpanel - cPanel News(from reseller)
#
# returns: returns true if exists
#
sub does_news_type_exist {
    my %ARGS = @_;    # The argument always comes as a hash value. This is a consequence of using API2 structure.

    my $news_type = $ARGS{"type"};

    if ($news_type) {
        my $owner = get_owner();
        if ( $news_type eq "global" ) {
            return _does_given_news_file_exist( get_global_news_file() );
        }
        elsif ( $news_type eq "resold" ) {
            if ( $owner && $owner ne 'root' && ( $owner eq $Cpanel::user || ( Cpanel::PwCache::getpwnam($owner) )[0] ne '' ) ) {
                return _does_given_news_file_exist( get_resold_news_file() );
            }
        }
        elsif ( $news_type eq "cpanel" ) {
            return _does_given_news_file_exist( get_cpanel_news_file($owner) );
        }
    }
    return 0;
}

#
# method: _does_given_news_file_exist
#   This method checks the content of a given file to decide if it exists.
#
# param: $news_type_file- path to a type of news file.
# returns: returns true if exists
#
sub _does_given_news_file_exist {
    my $news_type_file = shift;

    return 0 unless $news_type_file && -r $news_type_file;

    # NOTE: -z file operator returns true if file size is zero.
    my $file_has_content = ( -e $news_type_file && !-z _ ) ? 1 : 0;
    return $file_has_content;
}

my $allow_demo = { allow_demo => 1 };

our %API = (
    does_news_exist      => $allow_demo,
    does_news_type_exist => $allow_demo,
    get_news             => $allow_demo,
);

sub api2 {
    my ($func) = @_;
    return { %{ $API{$func} } } if $API{$func};
    return;
}

*api2_does_news_exist      = \&does_news_exist;
*api2_does_news_type_exist = \&does_news_type_exist;
*api2_get_news             = \&get_news;

1;
