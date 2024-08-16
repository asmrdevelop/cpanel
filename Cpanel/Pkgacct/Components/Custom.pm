package Cpanel::Pkgacct::Components::Custom;

# cpanel - Cpanel/Pkgacct/Components/Custom.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent 'Cpanel::Pkgacct::Component';

use Cpanel::LoadModule::Custom ();
use Cpanel::Output             ();

use Try::Tiny;

=encoding utf-8

=head1 NAME

Cpanel::Pkgacct::Components::Custom - A pkgacct component module perform custom pkgacct modules

=head1 SYNOPSIS

    use Cpanel::Config::LoadCpConf;
    use Cpanel::Pkgacct;
    use Cpanel::Pkgacct::Components::Custom;
    use Cpanel::Output::Formatted::Terminal;

    my $user = 'root';
    my $work_dir = '/root/';
    my $pkgacct = Cpanel::Pkgacct->new(
        'is_incremental'    => 1,
        'is_userbackup'     => 1,
        'is_backup'         => 1,
        'user'              => $user,
        'new_mysql_version' => 'default',
        'uid'               => ( ( Cpanel::PwCache::getpwnam( $user ) )[2] || 10 ),
        'suspended'         => 1,
        'work_dir'          => $work_dir,
        'dns_list'          => 1,
        'domains'           => [],
        'now'               => time(),
        'cpconf'            => scalar Cpanel::Config::LoadCpConf::loadcpconf(),
        'OPTS'              => { 'db_backup_type' => 'all' },
        'output_obj'        => Cpanel::Output::Formatted::Terminal->new(),
    );

    $pkgacct->build_pkgtree($work_dir);
    $pkgacct->perform_component("Custom");

=head1 DESCRIPTION

This module implements a C<Cpanel::Pkgacct::Component> module. It is responsible for running
3rdparty and custom account package modules.

=cut

=head2 perform()

This function will check the custom pkgacct component directory, load, then call
perform on each component.

B<Returns>: C<1>

=cut

sub perform {
    my ($self) = @_;

    my @output_args = ( $Cpanel::Output::SOURCE_NONE, $Cpanel::Output::COMPLETE_MESSAGE, $Cpanel::Output::PREPENDED_MESSAGE );    # No source, not a partial message, prepend a timestamp
    my $output_obj  = $self->get_output_obj();

    my @components = $self->get_custom_components();
    for my $component (@components) {

        $output_obj->out( "Performing “$component” component....", @output_args );

        my $err;
        try {
            my $instance = $self->get_component_object($component);
            $instance->perform();
        }
        catch {
            $err = $_;
        };

        if ($err) {
            if ( eval { $err->isa('Cpanel::Exception::ModuleLoadError') } ) {
                $output_obj->warn( "The custom pkgacct component “$component” could not be loaded.", @Cpanel::Pkgacct::NOT_PARTIAL_TIMESTAMP );
            }
            else {
                require Cpanel::Exception;
                $output_obj->warn( "The custom pkgacct component “$component” failed due to an error: " . Cpanel::Exception::get_string($err), @Cpanel::Pkgacct::NOT_PARTIAL_TIMESTAMP );
            }
        }

        $output_obj->out( "Completed “$component” component.\n", @output_args );
    }

    @components ? $output_obj->out( "All custom components have been performed.\n", @output_args ) : $output_obj->out( "No custom components to perform.\n", @output_args );

    return 1;
}

=head2 get_custom_components()

This function checks /var/cpanel/perl for modules matching the Cpanel::Pkgacct::Component namespace.

B<Returns>: An array of module names under the namespace Cpanel::Pkgacct::Component. So, each module is represented by $module
to construct the full namespace please use do "Cpanel::Pkgacct::Component::$module".

=cut

sub get_custom_components {
    my ($self) = @_;

    return Cpanel::LoadModule::Custom::list_modules_for_namespace('Cpanel::Pkgacct::Components');
}

=head2 get_component_object()

This function takes in component module names in the format of get_custom_components's return. E.g. "$component" of "Cpanel::Pkgacct::Components::$component".

B<Returns>: C<Cpanel::Pkgacct::Components> object for the specified $component module.

=cut

sub get_component_object {
    my ( $self, $component ) = @_;
    my $module = "Cpanel::Pkgacct::Components::$component";
    Cpanel::LoadModule::Custom::load_perl_module($module);
    return "$module"->new( %{ $self->get_attrs() } );
}

1;
