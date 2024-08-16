package Cpanel::Config::ConfigObj::Driver::WpToolkitACL;

use strict;

use parent  qw(Cpanel::Config::ConfigObj::Interface::Config::v1);

our $VERSION = '1.0';

sub init {

    my $class        = shift;
    my $software_obj = shift;

    my $WpToolkitACL_defaults = {
        'thirdparty_ns' => "WpToolkitACL",
        'meta'          => {},
    };

    Cpanel::LoadModule::load_perl_module('Cpanel::Config::LoadCpConf');

    my $self = $class->SUPER::base( $WpToolkitACL_defaults, $software_obj );

    return $self;
}

sub info {
    my ($self)   = @_;
    my $meta_obj = $self->meta();
    my $abstract = $meta_obj->abstract();
    return $abstract;
}

sub acl_desc {
    return [
        {
            'acl'              => 'wp-toolkit',
            'default_value'    => 0,
            'default_ui_value' => 1,
            'name'             => 'Access to WP Toolkit',
            'acl_subcat'       => 'WP Toolkit',
        },
    ];
}

1;
