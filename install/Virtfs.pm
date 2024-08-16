package Install::Virtfs;    ## no critic (RequireFilenameMatchesPackage)

# cpanel - install/Virtfs.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use base qw( Cpanel::Task );

use strict;
use Cpanel::SafeFile ();

our $VERSION     = '1.0';
our $filename    = '0_README_BEFORE_DELETING_VIRTFS';
our @directories = qw(/home /home/virtfs);

=head1 DESCRIPTION

    Create a '0_README_BEFORE_DELETING_VIRTFS' file
    in /home and /home/virtfs to warn customer about
    potential damages of removing virtfs directories.

=over 1

=item Type: Fresh Install, Sanity

=item Frequency: once

=item EOL: never

=back

=cut

exit __PACKAGE__->runtask() unless caller;

sub new {
    my $proto = shift;
    my $self  = $proto->SUPER::new;

    $self->set_internal_name('virtfs');

    return $self;
}

sub _get_text {
    return <<EOM;
The /home/virtfs directory contains critical operating system files. If you
remove /home/virtfs, or any directories under /home/virtfs, you will cause
irreparable damage to your operating system. Do not remove /home/virtfs, or any
directories under /home/virtfs, unless you have tested, up-to-date backups.

You should ignore any disk usage warnings you receive that are associated with
the /home/virtfs directory!

For more information about the /home/virtfs directory, visit the documentation
at https://go.cpanel.net/virtfsdoc
EOM
}

sub already_performed {
    foreach my $dir (@directories) {
        return 0 unless -e "$dir/$filename";
    }
    return 1;
}

sub perform {
    my $self = shift;

    foreach my $dir (@directories) {
        mkdir( $dir, 0711 );

        if ( my $lock = Cpanel::SafeFile::safeopen( my $fh, ">", "$dir/$filename" ) ) {
            print {$fh} _get_text();
            Cpanel::SafeFile::safeclose( $fh, $lock );
        }
    }

    return 1;
}

1;

__END__
