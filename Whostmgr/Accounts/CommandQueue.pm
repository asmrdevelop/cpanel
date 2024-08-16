package Whostmgr::Accounts::CommandQueue;

# cpanel - Whostmgr/Accounts/CommandQueue.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# A modular system for executing command queues on an account.
#
# This is a mix-in class. See subclasses for usage examples.
#----------------------------------------------------------------------

use strict;

use base qw(
  Cpanel::AttributeProvider
);

use Cpanel::CommandQueue ();
use Cpanel::LoadModule   ();

#----------------------------------------------------------------------
# Abstract methods

sub _helper_modules_to_use {
    die 'ABSTRACT method!';
}

sub _helper_module_namespace_root {
    die 'ABSTRACT method!';
}

#----------------------------------------------------------------------

#Called by subclasses.
#
#%opts is (all required):
#   username
#   action      - the function in the helper modules to call for the action
#   undo_action - the “paired” undo function in the helper modules
#
#Look at Whostmgr::Accounts::Suspend and W::A::Unsuspend for an example.
#
sub _init_and_do_action {
    my ( $class, %opts ) = @_;

    die "Need username!" if !length $opts{'username'};

    my $self = $class->SUPER::new();

    my $undo_action = delete $opts{'undo_action'};

    $self->import_attrs( \%opts );

    my $queue = Cpanel::CommandQueue->new();

    my $action   = $self->get_attr('action');
    my $username = $self->get_attr('username');

    my $helper_root = $self->_helper_module_namespace_root();

    #Load all the modules first...
    for my $module ( $self->_helper_modules_to_use() ) {
        my $full_module = $helper_root . "::$module";
        Cpanel::LoadModule::load_perl_module($full_module);
    }

    for my $module ( $self->_helper_modules_to_use() ) {
        my $full_module = $helper_root . "::$module";

        my $do_cr   = $full_module->can($action)      or die "$full_module can’t “$action”!";
        my $undo_cr = $full_module->can($undo_action) or die "$full_module can’t “$undo_action”!";

        $queue->add(
            sub { $do_cr->($username) },
            sub { $undo_cr->($username) },
            "undo $module",
        );
    }

    $queue->run();

    return $self;
}

1;
