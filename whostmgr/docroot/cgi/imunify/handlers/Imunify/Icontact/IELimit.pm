package Cpanel::iContact::Class::Imunify::IELimit;

use strict;

use Cpanel::DIp::MainIP;
use Cpanel::Hostname;
use Imunify::Utils;

use parent qw(
    Cpanel::iContact::Class
);

sub _required_args {
    my ($class) = @_;

    return (
        $class->SUPER::_required_args(),
        $class->_my_args(),
    );
}

sub _template_args {
    my ($class) = @_;
    my $base_url = 'cgi/imunify/handlers/index.cgi#/360';

    # in old versions of cPanel there is no getmainsharedip()
    my $mainip = Cpanel::DIp::MainIP->can('getmainsharedip')
        ? Cpanel::DIp::MainIP->getmainsharedip()
        : Cpanel::DIp::MainIP->getpublicmainserverip();

    my %template_args = (
        $class->SUPER::_template_args(),
        'hostname' => Cpanel::Hostname::gethostname(),
        'mainip'   => $mainip,
        'base_url'   => $base_url,
        map { $_ => $class->{'_opts'}{$_} } $class->_my_args(),
    );

    return %template_args;
}

sub _my_args {
    return qw(params);
}

1;
