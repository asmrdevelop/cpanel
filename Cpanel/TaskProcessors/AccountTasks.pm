package Cpanel::TaskProcessors::AccountTasks;

# cpanel - Cpanel/TaskProcessors/AccountTasks.pm     Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

{

    package Cpanel::TaskProcessors::AccountTasks::RemoveHomedir;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;

        my ( $user, $path ) = $task->args();
        return if !-e $path;    # already removed by another process

        require Cpanel::Homedir::Modify;
        require Cpanel::IONice;

        if ( $path !~ m{/\.remove_homedir$} ) {
            die "Cannot remove invalid path: $path";
        }
        Cpanel::IONice::ionice( 'best-effort', 6 );
        Cpanel::Homedir::Modify::remove_homedir( $user, $path );
        return;
    }

    sub deferral_tags {
        return qw/remove_homedir/;
    }
}

{

    package Cpanel::TaskProcessors::AccountTasks::ApplyPackageToAccounts;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    # Only allow one apply_package task to run at a time
    sub deferral_tags {
        return qw/apply_package/;
    }

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;

        my ( $package_uri, $user ) = $task->args();

        require Cpanel::Encoder::URI;
        my $package = Cpanel::Encoder::URI::uri_decode_str($package_uri);

        require Cpanel::Locale;
        my $locale = Cpanel::Locale->new();

        $logger->info( $locale->maketext( "Applying the package settings from the “[_1]” package as the user “[_2]”.", $package, $user ) );

        require Whostmgr::Packages::Apply;
        my ( $success, $failed ) = Whostmgr::Packages::Apply::apply_package_to_accounts( $package, $user );

        if (@$failed) {

            require Cpanel::Exception;
            foreach my $failure (@$failed) {

                my $msg = $locale->maketext(
                    "There was an error while trying to apply the package settings from the “[_1]” package to the account “[_2]”: [_3]",
                    $package,
                    $failure->{user},
                    Cpanel::Exception::get_string( $failure->{error} ),
                );

                $logger->warn($msg);
            }

        }

        my $finish_msg = $locale->maketext(
            "Finished applying the package settings from the “[_1]” package: [quant,_2,accounts,account] successfully updated.",
            $package,
            scalar @$success,
        );

        $logger->info($finish_msg);

        return;
    }

}

sub to_register {
    return (
        [ 'remove_homedir',            Cpanel::TaskProcessors::AccountTasks::RemoveHomedir->new() ],
        [ 'apply_package_to_accounts', Cpanel::TaskProcessors::AccountTasks::ApplyPackageToAccounts->new() ],
    );
}

1;
__END__

=head1 NAME

Cpanel::TaskProcessors::AccountTasks - Task processor for Account maintenance

=head1 VERSION

This document describes Cpanel::TaskProcessors::AccountTasks version 0.0.1


=head1 SYNOPSIS

    use Cpanel::TaskProcessors::AccountTasks;

=head1 DESCRIPTION

Implement the code for the I<remove_homedir>  Tasks. These are not intended to be used directly.

=head1 INTERFACE

This module defines one subclass of L<Cpanel::TaskQueue::FastSpawn> and a package method.

=head2 Cpanel::TaskProcessors::AccountTasks::to_register

Used by the L<cPanel::TaskQueue::PluginManager> to register the included classes.

=head2 Cpanel::TaskProcessors::AccountTasks::RemoveHomedir;

This is a thin wrapper around Cpanel::Homedir::Modify::remove_homedir

=head1 INCOMPATIBILITIES

None reported.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2019, cPanel, L.L.C All rights reserved.
