package Cpanel::Themes::SiteMap;

# cpanel - Cpanel/Themes/SiteMap.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Debug              ();
use Cpanel::Exception          ();
use Cpanel::Themes::Serializer ();
use Try::Tiny;

###
# new( %args )
#
# Construct the Cpanel::Themes::SiteMap object
#
# params:
#   format => The format of the theme, the only valid value is DynamicUI at this time
#   path => 'The full filesystem pat to the theme'

sub new {
    my ( $class, %OPTS ) = @_;

    my $self = bless {
        'format' => $OPTS{'format'} || 'DynamicUI',    # Default to dynamicui, to change when we have non-DynamicUI themes
        'links'  => [],
        'groups' => [],
        'path'   => $OPTS{'path'},
        'user'   => $OPTS{'user'},
        'loaded' => 0,
    }, $class;

    return $self;
}

# load the theme's config from the path in the object
sub load {
    my ($self) = @_;

    my ($err);
    try {
        my $s_object = Cpanel::Themes::Serializer::get_serializer_obj( $self->{'format'}, $self->{'path'}, $self->{'user'} );
        $self->{'serializer_obj'} = $s_object;
        $self->{'groups'}         = $s_object->groups();
        $self->{'links'}          = $s_object->links();
        $self->{'loaded'}         = 1;
    }
    catch {
        $err = $_;
    };
    if ($err) {
        my $error_string = Cpanel::Exception::get_string($err);
        Cpanel::Debug::log_warn("An error occurred while loading the theme $self->{'format'}: $error_string");
        return 0;
    }
    return 1;
}

# we don't actually care what these return normally, however this is useful for testing.
sub add_link {
    my ( $self, $link_obj ) = @_;

    return $self->{'serializer_obj'}->add_link($link_obj);
}

# we don't actually care what these return normally, however this is useful for testing.
sub add_group {
    my ( $self, $group_obj ) = @_;

    return $self->{'serializer_obj'}->add_group($group_obj);
}

# we don't actually care what these return normally, however this is useful for testing.
sub delete_link {
    my ( $self, $link_obj ) = @_;

    return $self->{'serializer_obj'}->delete_link($link_obj);
}

# we don't actually care what these return normally, however this is useful for testing.
sub delete_group {
    my ( $self, $group_obj ) = @_;

    return $self->{'serializer_obj'}->delete_group($group_obj);
}

1;
