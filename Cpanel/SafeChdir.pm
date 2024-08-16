
# cpanel - Cpanel/SafeChdir.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::SafeChdir;

=head1 NAME

Cpanel::SafeChdir

=head1 USAGE

use Cwd ();

my $current = Cwd::getcwd();

{
    my $safedir = Cpanel::SafeChdir->new('some/new/path');

    my $new = Cwd::getcwd();
    if ($new ne $current) {
        print "Changed to $new\n";
    }
}

if (Cwd::getcwd() eq $current) {
    print "Back to original directory\n";
}

=head1 DESCRIPTION

This module will change to a given dirctory in the current scope but
once the object leaves that scope it will return you to the previous
directory.

=cut

use strict;
use Cwd            ();
use Cpanel::Logger ();

my $logger = Cpanel::Logger->new();

sub new {
    my ( $class, $path ) = @_;

    my $self = {
        'current_directory' => Cwd::getcwd(),
    };

    die "$path does not exist.\n" if !-d $path;

    chdir($path) or die "Unable to change to $path.\n";

    return bless $self, $class;
}

sub DESTROY {
    my ($self) = @_;

    my $original_dir = $self->{'current_directory'};
    chdir($original_dir) or $logger->warn("Unable to change back to $original_dir");
}

1;
