package Cpanel::Themes::Serializer::DynamicUI;

# cpanel - Cpanel/Themes/Serializer/DynamicUI.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::ArrayFunc::Map        ();
use Cpanel::Themes::Assets::Link  ();
use Cpanel::Themes::Assets::Group ();
use Cpanel::Exception             ();
use Cpanel::ConfigFiles           ();
use Cpanel::FileUtils::Copy       ();
use Cpanel::DynamicUI::Parser     ();
use Cpanel::DynamicUI::Loader     ();
use Cpanel::AcctUtils::Owner      ();
use Cpanel::Themes::Utils         ();
use Cpanel::cPAddons::Class       ();
use Cpanel::PwCache               ();

use parent 'Cpanel::Themes::Serializer::Base';

my %SKIP_LOAD_IMGTYPES = (
    'heading'    => 1,
    'compleximg' => 1,
    'ui'         => 1,
    'logo'       => 1,
    'css'        => 1,
    'preview'    => 1
);
my %SKIP_LOAD_TYPES = ( 'html' => 1 );

# parse the files, put into arrays of hashes
#
# This function is expect to build the following attributes in the class:
#
# links - An arrayref of Cpanel::Themes::Assets::Link objects
# groups - An arrayref of Cpanel::Themes::Assets::Group objects
sub build_data_tables {
    my ($self) = @_;

    my $dui_entries = $self->load();

    my ( %links, %groups, @extras, $site_software_obj );

    # Some entries simply specify a file which is to be skipped
    # From the public documentation:
    # To hide an icon or group from the cPanel Home interface,
    # add the following entry to a dynamicui file that loads after the file that contains the object to hide:
    # file=>item_to_hide,skipobj=>1
    my %entries_to_skip = map { $_->{'file'} => 1 } grep { $_->{'skipobj'} and $_->{'file'} } @{$dui_entries};

  ENTRY:
    foreach my $entry ( @{$dui_entries} ) {

        # at this moment we only care about groups & icons
        # I hope to add more into this later on, the rest gets stashed into the @extras array.
        if ( $entry->{'file'} ) {

            next if $entries_to_skip{ $entry->{'file'} };

            # If we do not skip these legacy x3 items
            # notifications that call get_users_links will
            # fail to go out
            next if $entry->{'imgtype'} && $SKIP_LOAD_IMGTYPES{ $entry->{'imgtype'} };
            next if $entry->{'type'}    && $SKIP_LOAD_TYPES{ $entry->{'type'} };

            # is an image, can be numerous types in the DUI system
            if ( exists $entry->{'groupdesc'} ) {

                # groups are determined by the "groupdesc" entry existing (seriously)
                my $group_obj = $self->_dui2group($entry);
                $groups{ $group_obj->{'id'} } = $group_obj;
                next ENTRY;
            }
            else {
                # if no group desc exists, it's probably an icon
                my $link_obj = eval { $self->_dui2link($entry); };
                if ($link_obj) {
                    $links{ $link_obj->{'id'} } = $link_obj;
                    if ( $entry->{'file'} eq 'site_software' ) {
                        $site_software_obj = $link_obj;
                    }
                }
                next ENTRY;
            }
        }
        push @extras, $entry;
    }
    $self->{'links'}  = [ map { $links{$_} } sort keys %links ];
    $self->{'groups'} = [ map { $groups{$_} } sort keys %groups ];
    $self->{'extras'} = \@extras;

    if ($site_software_obj) {
        my @cpaddon_feature_desc = Cpanel::cPAddons::Class->new()->load_cpaddon_feature_descs();
        foreach my $cpaddon (@cpaddon_feature_desc) {
            my ( $addon_module, $addon_description ) = @{$cpaddon};
            my $addon_implements = ( split( m{:}, $addon_module ) )[-1];
            my $clone            = $site_software_obj->clone();
            $clone->{'uri'} .= "?addon=" . $addon_module;
            $clone->{'implements'} = "Site_Software_$addon_implements";
            push @{ $self->{'links'} }, $clone;
        }
    }

    return 1;
}

sub add_link {
    my ( $self, @links ) = @_;
    @links = @{ $links[0] } if ref $links[0] eq 'ARRAY';

    foreach my $link (@links) {
        $self->_save($link);
    }

    return;
}

sub add_group {
    my ( $self, @groups ) = @_;
    @groups = @{ $groups[0] } if ref $groups[0] eq 'ARRAY';

    foreach my $group (@groups) {
        $self->_save($group);
    }

    return;
}

sub delete_link {
    my ( $self, @links ) = @_;
    @links = @{ $links[0] } if ref $links[0] eq 'ARRAY';

    foreach my $link (@links) {
        $self->_delete($link);
    }

    return;
}

sub delete_group {
    my ( $self, @groups ) = @_;
    @groups = @{ $groups[0] } if ref $groups[0] eq 'ARRAY';

    foreach my $group (@groups) {
        $self->_delete($group);
    }

    return;
}

#####
#
# CONVERTERS
#
#####

#convert a dynamicui entry into a link object
sub _dui2link {
    my ( $self, $entry ) = @_;

    my %attributes;

    #TODO: abstract this, we'll need this sort of logic all over the place
    my $onclick;
    foreach my $param ( keys %{$entry} ) {
        my $value = $entry->{$param};

        # could probaly be done as a dispatch table,but meh.
        if ( $param eq 'itemorder' ) {
            $attributes{'order'} = $value;
        }
        elsif ( $param eq 'file' ) {
            $attributes{'icon'} = $self->_get_icon_path($value);
            $attributes{'id'}   = $value;
        }
        elsif ( $param eq 'description' ) {
            $attributes{'name'} = $value;
        }
        elsif ( $param eq 'group' ) {
            $attributes{'group_id'} = $value;
        }
        elsif ( $param eq 'url' ) {
            $attributes{'uri'} = $value;
        }
        elsif ( $param eq 'target' ) {
            $attributes{'target'} = $value;
        }
        elsif ( $param eq 'base64_png_image' ) {
            $attributes{'base64_png_image'} = $value;
        }
        elsif ( $param eq 'acontent' ) {
            $attributes{'a_contents'} = $value;
        }
        elsif ( $param eq 'onclick' ) {

            # cannot alter a_contents here:
            #   we have no guarantee that it's going to be set before this
            #   using a sort on the keys will fix it, but this is tricky
            $onclick = " onclick=\"$value\";";
        }
        elsif ( $param eq 'feature' ) {
            $attributes{'feature'} = $value;
        }
        elsif ( $param eq 'if' ) {
            $attributes{'if'} = $value;
        }
        elsif ( $param eq 'searchtext' ) {
            $attributes{'search_text'} = $value;
        }
        elsif ( $param eq 'implements' ) {
            $attributes{'implements'} = $value;
        }
    }

    # we cannot rely on the order of keys when looping
    if ( defined $onclick ) {
        $attributes{'a_contents'} = '' unless defined $attributes{'a_contents'};
        $attributes{'a_contents'} .= $onclick;
    }

    return Cpanel::Themes::Assets::Link->new(%attributes);
}

# convert a Cpanel::Themes::Assets::Link obj to a hashref suitable for serialization for DUI
*link2dui = \&_link2dui;

sub _link2dui {
    my ( $self, $link_obj ) = @_;

    my %dui = (
        'subtype' => 'img',
        'imgtype' => 'icon',
        'type'    => 'image',
        'width'   => $self->{'config'}->{'icon'}->{'feature'}->{'width'},
        'height'  => $self->{'config'}->{'icon'}->{'feature'}->{'height'},
    );

    foreach my $attribute ( keys %{$link_obj} ) {
        next if !defined $link_obj->{$attribute};    # skips stuff with undef values
        my $value = $link_obj->{$attribute};

        if ( $attribute eq 'name' ) {
            $dui{'itemdesc'}    = $value;
            $dui{'description'} = $value;
        }
        elsif ( $attribute eq 'id' ) {
            $dui{'file'} = $value;
        }
        elsif ( $attribute eq 'uri' ) {
            $dui{'url'} = $value;
        }
        elsif ( $attribute eq 'target' ) {
            $dui{'target'} = $value;
        }
        elsif ( $attribute eq 'if' ) {
            $dui{'if'} = $value;
        }
        elsif ( $attribute eq 'base64_png_image' ) {
            $dui{'base64_png_image'} = $value;
        }
        elsif ( $attribute eq 'a_contents' ) {
            $dui{'acontents'} = $value;
        }
        elsif ( $attribute eq 'feature' ) {
            $dui{'feature'} = $value;
        }
        elsif ( $attribute eq 'group_id' ) {
            $dui{'group'} = $value;
        }
        elsif ( $attribute eq 'order' ) {
            $dui{'itemorder'} = $value;
        }
        elsif ( $attribute eq 'search_text' ) {
            $dui{'searchtext'} = $value;
        }
        elsif ( $attribute eq 'implements' ) {
            $dui{'implements'} = $value;
        }
    }

    return \%dui;
}

# convert a dynamic ui group entry to a group object
sub _dui2group {
    my ( $self, $entry ) = @_;

    my %attributes;

    #TODO: abstract this, we'll need this sort of logic all over the place
    foreach my $param ( keys %{$entry} ) {
        my $value = $entry->{$param};
        next unless defined $value;

        # could probaly be done as a dispatch table,but meh.
        if ( $param eq 'grouporder' ) {
            $attributes{'order'} = $value;
        }
        elsif ( $param eq 'file' ) {
            $attributes{'icon'} = $value . '.';
            $attributes{'icon'} .= $self->{'config'}->{'icon'}->{'format'} if $self->{'config'}->{'icon'}->{'format'};
            $attributes{'id'} = $value;
        }
        elsif ( $param eq 'description' ) {
            $attributes{'name'} = $value;
        }
    }

    return Cpanel::Themes::Assets::Group->new(%attributes);
}

*group2dui = \&_group2dui;

sub _group2dui {
    my ( $self, $group_obj ) = @_;

    my %dui = (
        'subtype' => 'img',
        'imgtype' => 'icon',
        'type'    => 'image',
        'width'   => $self->{'config'}->{'icon'}->{'group'}->{'width'},
        'height'  => $self->{'config'}->{'icon'}->{'group'}->{'height'},
    );

    foreach my $attribute ( keys %{$group_obj} ) {
        next if !defined $group_obj->{$attribute};    # skips stuff with undef values
        my $value = $group_obj->{$attribute};

        if ( $attribute eq 'name' ) {
            $dui{'groupdesc'}   = $value;
            $dui{'description'} = $value;
        }
        elsif ( $attribute eq 'id' ) {

            # ensure that the file entry always starts with group_
            my $file = $value;
            $file = 'group_' . $file;

            $dui{'file'}  = $file;
            $dui{'group'} = $value;
        }
        elsif ( $attribute eq 'order' ) {
            $dui{'grouporder'} = $value;
        }
    }

    return \%dui;
}

# Get the path that an icon SHOULD exist
sub _get_icon_path {
    my ( $self, $id ) = @_;
    my $path = $self->{'docroot'};
    $path .= ${self}->{'config'}->{'icon'}->{'path'} if defined ${self}->{'config'}->{'icon'}->{'path'};
    $path .= $id . '.';
    $path .= $self->{'config'}->{'icon'}->{'format'} if $self->{'config'}->{'icon'}->{'format'};
    return $path;
}

#####
#
# FILE MANAGEMENT
#
#####

####
# _save( $link_obj )
#
# save a dynamiui object to the file system
#
# This will save directly to $theme_docroot/dynamicui/dynamicui_${id}.conf
#####
sub _save {
    my ( $self, $asset ) = @_;

    my $dui_hr;
    my $icon_prefix = '';
    if ( ref $asset eq 'Cpanel::Themes::Assets::Group' ) {
        $dui_hr      = $self->_group2dui($asset);
        $icon_prefix = 'group_';
    }
    elsif ( ref $asset eq 'Cpanel::Themes::Assets::Link' ) {
        $dui_hr = $self->_link2dui($asset);
    }

    my $save_dir  = $self->{'docroot'} . '/dynamicui';
    my $save_path = $save_dir . '/dynamicui_' . $dui_hr->{'file'} . '.conf';

    # generate contents for DUI file
    my $dui_string = '';
    foreach my $key ( sort keys %{$dui_hr} ) {
        next unless defined $dui_hr->{$key};
        $dui_hr->{$key} = "\$LANG{'$dui_hr->{$key}'}"
          if Cpanel::ArrayFunc::Map::mapfirst( sub { $key eq shift }, qw(name description itemdesc groupdesc) );
        $dui_string .= $key . '=>' . $dui_hr->{$key} . ',';
    }
    $dui_string =~ s/,$/\n/;

    #copy icon into $docroot/branding
    if ( exists $asset->{'icon'} && defined $asset->{'icon'} && defined $asset->{'id'} ) {

        # get teh extension from the provided file
        my ($extension) = $asset->{'icon'} =~ m/.+\.([a-z]+)$/;
        $extension = 'jpg' if $extension eq 'jpeg';
        my $icon_destination = $self->{'docroot'};

        $icon_destination .= ${self}->{'config'}->{'icon'}->{'path'} if defined ${self}->{'config'}->{'icon'}->{'path'};
        $icon_destination .= '/' . $icon_prefix . $asset->{'id'} . '.' . $extension;

        # put the icon file into place
        if ( !Cpanel::FileUtils::Copy::safecopy( $asset->{'icon'}, $icon_destination ) ) {
            die Cpanel::Exception::create(
                'IO::FileCopyError',
                [
                    'source'      => $asset->{'icon'},
                    'destination' => $icon_destination,
                ]
            );
        }
    }

    # make sure the dynamicui/ directory is available
    if ( !-d $save_dir ) {
        mkdir $save_dir or die Cpanel::Exception::create( 'IO::DirectoryCreateError', [ path => $save_dir, error => $! ] );
    }

    # write our dynamic ui file
    open my $dui_fh, '>', $save_path or die Cpanel::Exception::create( 'IO::FileOpenError', [ 'path' => $save_path, 'error' => $! ] );
    print $dui_fh $dui_string;
    close $dui_fh;

    return;
}

####
# _delete( $link_obj )
#
# delete a dynamiui object from the file system
#
# This will remove $theme_docroot/dynamicui/dynamicui_${id}.conf
#####
sub _delete {
    my ( $self, $asset ) = @_;

    my $dui_hr;
    my $icon_prefix = '';
    if ( ref $asset eq 'Cpanel::Themes::Assets::Group' ) {
        $dui_hr      = $self->_group2dui($asset);
        $icon_prefix = 'group_';
    }
    elsif ( ref $asset eq 'Cpanel::Themes::Assets::Link' ) {
        $dui_hr = $self->_link2dui($asset);
    }

    my $target_dir  = $self->{'docroot'} . '/dynamicui';
    my $target_path = $target_dir . '/dynamicui_' . $dui_hr->{'file'} . '.conf';

    # remove icons from $docroot/branding
    if ( $asset->{'icon'} && $asset->{'id'} ) {

        # get the extension from the provided file
        my ($extension) = $asset->{'icon'} =~ m/.+\.([a-z]+)$/;
        $extension = 'jpg' if $extension eq 'jpeg';
        my $icon_destination = $self->{'docroot'};
        $icon_destination .= ${self}->{'config'}->{'icon'}->{'path'} if defined ${self}->{'config'}->{'icon'}->{'path'};
        $icon_destination .= '/' . $icon_prefix . $asset->{'id'} . '.' . $extension;

        unlink $icon_destination if -f $icon_destination;
    }

    # remove dynamic ui file
    unlink $target_path if -f $target_path;

    return;
}

###
# _read( $path );
#
# Read in a file containing branding data
#
# Get back array of objects in file.
####
sub _read {
    my ( $self, $source ) = @_;

    if ( $source->{'allow_legacy'} ) {
        return Cpanel::DynamicUI::Parser::read_dynamicui_file_allow_legacy( $source->{'file'} );
    }

    return Cpanel::DynamicUI::Parser::read_dynamicui_file( $source->{'file'} );
}

###
# get_sources( $docroot )
#
# Get a list of dynamicui files in a theme's document root
sub get_sources {
    my ($self)  = @_;
    my $docroot = $self->{'docroot'};
    my $user    = $self->{'user'} || 'root';

    my $theme        = Cpanel::Themes::Utils::get_theme_from_theme_root($docroot);
    my $owner        = Cpanel::AcctUtils::Owner::getowner($user);
    my $ownerhomedir = $owner eq 'root' ? $Cpanel::ConfigFiles::ROOT_CPANEL_HOMEDIR : Cpanel::PwCache::gethomedir($owner);
    my $dui_confs    = Cpanel::DynamicUI::Loader::list_dynamicui_confs_for_user_theme_brandingpkg(
        'theme'        => $theme,
        'user'         => $user,
        'ownerhomedir' => $ownerhomedir
    );

    return grep { -e $_->{'file'} } @$dui_confs;
}

1;
