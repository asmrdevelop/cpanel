package Cpanel::Umask;

# cpanel - Cpanel/Umask.pm                         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::Umask - Restore original umask when object goes out of scope

=head1 SYNOPSIS

 {
   my $umask_obj = Cpanel::Umask->new( 077 );
   #..do stuff that requires files to be created with owner-only permissions
 }
 #..do stuff where files will be created with default permissions (as modified by original umask)

=head1 DESCRIPTION

 This is basically CPAN's Umask::Local. That module would be fine here
 except for the awkwardness of adding new CPAN modules to our code.

 In particular, there are some places (e.g., fat-packing) where we
 try very hard to avoid CPAN dependencies. This module suits that purpose.

 Also, it seems desirable to complain more loudly when setting the umask back
 if, at change-back time, the current umask is not what we expect.

 Use this module to set the process umask and automatically switch
 back to the previous umask at the end of scope.

 e.g.:
 my $umask = umask;
 {
   my $umask_obj = Cpanel::Umask->new( 027 );
   #..do stuff
 }
 my $umask2 = umask;

 In the above code, $umask and $umask2 are the same, but "do stuff" will
 be have a umask of 027.

 This will warn if, when the object umask()s back to the
 original umask, the umask is not what it is expected to be.

=cut

use strict;

use parent qw(Cpanel::Finally);

sub new {
    my ( $class, $new ) = @_;

    my $old = umask();

    umask($new);

    return $class->SUPER::new(
        sub {
            my $cur = umask();

            #This error means that some piece of code is misbehaving
            #and not restoring the process's current directory.
            if ( $cur != $new ) {
                my ( $cur_o, $old_o, $new_o ) = map { '0' . sprintf( '%o', $_ ) } ( $cur, $old, $new );

                warn "I want to umask($old_o). I expected the current umask to be $new_o, but it’s actually $cur_o.";
            }

            umask($old);
        }
    );
}

1;
