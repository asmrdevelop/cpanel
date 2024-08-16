package Cpanel::Config::ConfigObj::Driver::Imunify360;

use strict;

use parent  qw(Cpanel::Config::ConfigObj::Interface::Config::v1);

our $VERSION = '1.0';

sub init {

    my $class        = shift;
    my $software_obj = shift;

    my $ACL_defaults = {
        'thirdparty_ns' => "Imunify360",
        'meta'          => {},
    };

    Cpanel::LoadModule::load_perl_module('Cpanel::Config::LoadCpConf');

    my $self = $class->SUPER::base( $ACL_defaults, $software_obj );

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
            'acl'              => 'software-imunify360',
            'default_value'    => 0,
            'default_ui_value' => 0,
            'name'             => 'Imunify360 plugin',
            'acl_subcat'       => 'Third-Party Services',
        },
    ];
}

1;
