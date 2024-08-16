
# cpanel - Cpanel/cPAddons/Filter.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::cPAddons::Filter;

use strict;
use warnings;

use Cpanel::DataStore ();

=head1 NAME

Cpanel::cPAddons::Filter

=head1 DESCRIPTION

Provides various list filter methods to limit which cPAddons are shown for various
operations.

Add modules to the /var/cpanel/conf/cpaddons/blacklist to make them unavailable in
WHM no matter what.

Add modules to the /var/cpanel/conf/cpaddons/deprecated to make them unavailable in
WHM if they are not installed.

=cut

our $CONF_PATH = '/var/cpanel/conf/cpaddons';

my $loaded;
my @blacklist;
our $BLACKLIST_FILE_PATH = "$CONF_PATH/blacklist";

my @deprecated;
our $DEPRECATED_FILE_PATH = "$CONF_PATH/deprecated";

# these addons are currently deprecated and a user cannot reenable them
use constant ADDONS_CURRENTLY_DEPRECATED => (
    "cPanel::Blogs::B2Evolution",
    "cPanel::Blogs::WordPress",
    "cPanel::Blogs::WordPressX",
    "cPanel::Bulletin_Boards::YaBB",
    "cPanel::Bulletin_Boards::phpBB",
    "cPanel::Bulletin_Boards::phpBB3",
    "cPanel::CMS::E107",
    "cPanel::CMS::Geeklog",
    "cPanel::CMS::Mambo",
    "cPanel::CMS::Nucleus",
    "cPanel::CMS::PostNuke",
    "cPanel::CMS::Soholaunch",
    "cPanel::CMS::Xoops",
    "cPanel::CMS::phpWiki",
    "cPanel::Chat::phpMyChat",
    "cPanel::Ecommerce::AgoraCart",
    "cPanel::Ecommerce::OSCommerce",
    "cPanel::Gallery::Coppermine",
    "cPanel::Guest_Books::Advanced_Guestbook",
    "cPanel::Support::cPSupport",
);

=head1 FUNCTIONS

=head2 _load() [PRIVATE]

Loads the blacklist and deprecated modules list from the file system.

=cut

sub _load {
    return if $loaded;

    if ( -e $BLACKLIST_FILE_PATH ) {
        my $bl_ref = Cpanel::DataStore::fetch_ref( $BLACKLIST_FILE_PATH, 1 );
        @blacklist = @$bl_ref;
    }

    if ( -e $DEPRECATED_FILE_PATH ) {
        @deprecated = @{ Cpanel::DataStore::fetch_ref( $DEPRECATED_FILE_PATH, 1 ) };
    }

    # these addons are always deprecated, even if not listed in the file
    push @deprecated, ADDONS_CURRENTLY_DEPRECATED;
    my %uniq = map { $_ => 1 } @deprecated;    # remove duplicates
    @deprecated = sort keys %uniq;

    $loaded = 1;

    return;
}

=head2 is_blacklisted(MODULE)

=head3 ARGUMENTS

=over

=item MODULE - string

A module name in the form:  cPanel::<type>::<name>

=back

=head3 RETURNS

boolean - true value if the module is blacklisted, false value otherwise.

=cut

sub is_blacklisted {
    my $module = shift;
    die "Parameter module missing." if !$module;
    _load()                         if !$loaded;
    return grep( /^\Q$module\E$/i, @blacklist ) ? 1 : 0;
}

=head2 is_deprecated(MODULE)

=head3 ARGUMENTS

=over

=item MODULE - string

A module name in the form:  cPanel::<type>::<name>

=back

=head3 RETURNS

boolean - true value if the module is deprecated, false value otherwise.

=cut

sub is_deprecated {
    my $module = shift;
    die "Parameter module missing." if !$module;
    _load()                         if !$loaded;
    return grep( /^\Q$module\E$/i, @deprecated ) ? 1 : 0;
}

=head2 update_blacklist(MODULE, ...)

Update the deprecated list to include the items.

=head3 ARGUMENTS

=over

=item MODULE - string

A module name in the form:  cPanel::<type>::<name>

You may provide multiple modules in the argument list.

=back

=cut

sub update_blacklist {
    my (@items) = @_;

    # Add the items to the blacklist
    _update( $BLACKLIST_FILE_PATH, @items );

    # Load the full blacklist, so we can remove any
    # out of sync items from the deprecated list.
    my $full_blacklist = Cpanel::DataStore::fetch_ref( $BLACKLIST_FILE_PATH, 1 );

    # Remove the blacklist items from the deprecated list
    return remove( $DEPRECATED_FILE_PATH, @$full_blacklist );
}

=head2 update_deprecated(MODULE, ...)

Update the deprecated list to include the items.

=head3 ARGUMENTS

=over

=item MODULE - string

A module name in the form:  cPanel::<type>::<name>

You may provide multiple modules in the argument list.

=back

=cut

sub update_deprecated {
    my (@items) = @_;
    return _update( $DEPRECATED_FILE_PATH, @items );
}

=head2 _update(FILE, MODULE, ...) [PRIVATE]

Update the list located at the file path to include the items.

=head3 ARGUMENTS

=over

=item FILE - String

Path to the conf file to store the list.

=item MODULE - string

A module name in the form:  cPanel::<type>::<name>

You may provide multiple modules in the argument list.

=back

=cut

sub _update {
    my ( $file, @items ) = @_;

    if ( !-e $file ) {
        mkdir $CONF_PATH if !-d $CONF_PATH;
        Cpanel::DataStore::store_ref( $file, \@items, ['0644'] );
    }
    else {
        my $conf_list = Cpanel::DataStore::fetch_ref( $file, 1 );
        my %exists    = map { $_ => 1 } @{$conf_list};

        # Only add the items that are not already there.
        foreach my $item (@items) {
            if ( !$exists{$item} ) {
                push @{$conf_list}, $item;
            }
        }
        Cpanel::DataStore::store_ref( $file, $conf_list, ['0644'] );
    }

    clear_cache();    # So the memory cache will update if its already filled.

    return;
}

=head2 remove(FILE, MODULE, ...)

Remove the listed items from the list at the file location

=head3 ARGUMENTS

=over

=item FILE - String

Path to the conf file to store the list.

=item MODULE - string

A module name in the form:  cPanel::<type>::<name>

You may provide multiple modules in the argument list.

=back

=cut

sub remove {
    my ( $file, @to_remove ) = @_;

    if ( -e $file ) {
        my $conf_list = Cpanel::DataStore::fetch_ref( $file, 1 );
        my %to_remove = map { $_ => 1 } @to_remove;

        my @new_list;

        # Only add the items that are not already there.
        foreach my $item (@$conf_list) {
            if ( !$to_remove{$item} ) {
                push @new_list, $item;
            }
        }
        Cpanel::DataStore::store_ref( $file, \@new_list, ['0644'] );
    }

    clear_cache();    # So the memory cache will update if its already filled.

    return;
}

=head2 clear_cache()

Clears the in-memory cache so the load will happen again.

This function does not accept any arguments.

=cut

sub clear_cache {
    @blacklist  = ();
    @deprecated = ();
    $loaded     = 0;
    return;
}

=head2 get_blacklisted_addons()

Fetches the list of blacklisted addon modules. Blacklisted modules should not
be used and will be uninstalled automatically when certain other operations happen.
Blacklisted addons can be removed manually as well.

=head3 RETURNS

ARRAY REF listing the addons that are blacklisted by their module name.

=cut

sub get_blacklisted_addons {
    _load() if !$loaded;
    return \@blacklist;
}

=head2 get_deprecated_addons()

Fetches the list of deprecated addon modules. Deprecated modules may not be installed, however,
if already installed, can be updated or removed.

=head3 RETURNS

ARRAY REF listing the addons that are deprecated by their module name.

=cut

sub get_deprecated_addons {
    _load() if !$loaded;
    return \@deprecated;
}

1;
