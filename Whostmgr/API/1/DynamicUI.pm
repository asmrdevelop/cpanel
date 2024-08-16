package Whostmgr::API::1::DynamicUI;

# cpanel - Whostmgr/API/1/DynamicUI.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Locale ();

use Whostmgr::Theme ();

use constant NEEDS_ROLE => {
    get_available_applications => undef,
};

=encoding utf-8

=head1 NAME

Whostmgr::API::1::DynamicUI - WHM API functions to manage dynamicui.conf files on the server.

=head1 SUBROUTINES

=over 4

=item get_available_applications( [file], [applications_list] )

Retrieves data from a dynamicui configuration file in JSON format. This function takes the
name of the configuration file. This file should exist under the theme document root, for
example, /usr/local/cpanel/whostmgr/docroot/themes/x. If it is not provided, the file name
defaults to dynamicui.conf. The function also takes an optional argument, applications_list,
a comma separated list of applications, and only retrieves information for applications in
the list if available.

Returns a hash reference that represents items listed in the configuration file. This list
has already been filtered using user's ACLs, and other server configurations, such as
dnsonly, CLOUDLINUX, etc, and should contain the following:

=over 4

=item groups

An array of hash references, each representing a group of applications. For example,

    [
        {
            "searchtext":"support"
            "group":"support"
            "dnsonly_ok":"dns"
            "groupdesc":"Support"
            "items":[
                {
                    "acl":"ACL=all"
                    "searchtext":"support create support ticket"
                    "itemdesc":"Create Support Ticket"
                    "dnsonly_ok":"dns"
                    "url":"/scripts7/create_support_ticket"
                    "group":"support"
                }
            ]
        }
    ]

This list may be empty if the user does not have access to any applications.

=back

=cut

sub get_available_applications {
    my ( $args, $metadata ) = @_;

    my $dynamicui_file = $args->{'file'};

    $dynamicui_file ||= 'dynamicui.conf';
    $dynamicui_file =~ s{\.\.|/}{}g;
    $dynamicui_file = _theme_root() . '/' . $dynamicui_file;

    unless ( -e $dynamicui_file ) {
        $metadata->{'reason'} = _locale()->maketext( 'The “[_1]” file does not exist.', $dynamicui_file );
        $metadata->{'result'} = 0;
        return;
    }

    require Whostmgr::DynamicUI::Loader;
    my $data = Whostmgr::DynamicUI::Loader::load_and_filter($dynamicui_file);

    unless ($data) {
        $metadata->{'reason'} = _locale()->maketext( 'The system failed to read “[_1]”.', $dynamicui_file );
        $metadata->{'result'} = 0;
        return;
    }

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'Ok';

    return ( $args->{'applications_list'} ? _process_list( $data, $args->{'applications_list'} ) : $data );
}

=item _process_list()

Only returns applications specified in the list. If no list is provided, then
all applications are returned.

=cut

sub _process_list {
    my ( $data, $wanted_list ) = @_;

    return $data unless $wanted_list;

    my %wanted = map { $_ ? ( $_ => 1 ) : () } split( /\s*,\s*/, $wanted_list );

    my @filtered_items;
    foreach my $group ( @{ $data->{'groups'} } ) {
        foreach my $item ( @{ $group->{'items'} } ) {
            my $app_name = ( split( /\./, $item->{'file'} ) )[0];
            push @filtered_items, $item if $wanted{$app_name};
        }
    }
    $data = {};
    $data->{'applications'} = \@filtered_items;

    return $data;
}

my $theme_root;
my $locale;

sub _theme_root {
    return $theme_root if $theme_root;

    return $theme_root = Whostmgr::Theme::getthemedir();
}

sub _locale {
    return $locale if $locale;

    return $locale = Cpanel::Locale->get_handle();
}

=back

=cut

1;
