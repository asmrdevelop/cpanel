package Cpanel::Chdir;

# cpanel - Cpanel/Chdir.pm                         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# Use this module to chdir() to a new location and automatically switch
# back to the previous working directory at the end of scope.
#
# e.g.:
# my $cwd = Cwd::getcwd();
# {
#   my $chdir = Cpanel::Chdir->new( '/some/new/dir' );
#   #..do stuff
# }
# my $cwd2 = Cwd::getcwd();
#
# In the above code, $cwd and $cwd2 are the same, but "do stuff" will
# be chdir()ed to /some/new/dir.
#
# This will warn if, when the object chdir()s back to the
# original directory, the cwd is not what it is expected to be.
#----------------------------------------------------------------------

use strict;
use warnings;

use Cwd ();

use Cpanel::Exception ();
use Cpanel::Finally   ();

sub new {
    my ( $class, $dir, %options ) = @_;

    # In Perl 5.22 and earlier, chdir(undef) is equivalent to chdir() is equivalent to chdir($ENV{HOME}).
    # Under certain type of file system failure (for instance, using an iSCSI mount), abs_path() can return undef.
    # These two behaviors in combination can cause for data within /root to be overwritten.
    # See SEC-299 for further information.

    if ( !defined $dir ) {
        die Cpanel::Exception::create( 'IO::ChdirError', [ error => "Target directory was not defined.", path => $dir ] );
    }

    my $new_dir = Cwd::abs_path($dir) || die Cpanel::Exception::create( 'IO::ChdirError', [ error => "Failed to find absolute path.",              path => $dir ] );
    my $old_dir = Cwd::getcwd()       || die Cpanel::Exception::create( 'IO::ChdirError', [ error => "Current directory could not be determined.", path => $dir ] );

    my $self = {
        _old_dir => $old_dir,
        _new_dir => $new_dir,
    };
    bless $self, $class;

    _checked_chdir($new_dir);

    $self->{'_finally'} = Cpanel::Finally->new(
        sub {
            my $cur_dir = Cwd::getcwd();

            #This error means that some piece of code is misbehaving
            #and not restoring the process's current directory.
            if ( defined $cur_dir && $cur_dir ne $new_dir ) {
                die "I want to chdir() back to “$old_dir”. I expected the current directory to be “$new_dir”, but it’s actually “$cur_dir”.";
            }

            #NOTE: This won't actually produce an exception since it's in a
            #DESTROY handler, but it will warn(). (cf. perldoc perl5140delta)
            #
            #http://perldoc.perl.org/perlobj.html#Destructors should describe
            #this behavior, but it hasn't been updated for 5.14. (RT #122753)
            _checked_chdir( $old_dir, $options{'quiet'} );
        }
    );

    return $self;
}

#NOTE: This has to be a static method to prevent DESTROY handler issues.
sub _checked_chdir {
    my ( $to_dir, $quiet ) = @_;

    local ( $!, $^E );
    my $success = chdir($to_dir);
    return if $quiet || $success;
    die Cpanel::Exception::create( 'IO::ChdirError', [ error => $!, path => $to_dir ] );
}

1;
