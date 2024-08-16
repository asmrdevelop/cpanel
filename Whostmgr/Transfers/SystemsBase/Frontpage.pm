package Whostmgr::Transfers::SystemsBase::Frontpage;

# cpanel - Whostmgr/Transfers/SystemsBase/Frontpage.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
#NOTE: This is a base module. See one of its subclasses to do real work.
#----------------------------------------------------------------------

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)

#use Whostmgr::Transfers::Modules   ();    # Module deps in Whostmgr::Transfers::Modules
use Cpanel::SafeFind        ();
use Cpanel::SafeFile        ();
use Cpanel::Security::Authz ();
use IO::Handle              ();

sub frontpage_excludes {

    # Requires --anchored option for gtar
    return map { './public_html/' . $_ } qw(
      postinfo.html
      _private
      _vti_bin
      _vti_cnf
      _vti_inf.html
      _vti_log
      _vti_pvt
      _vti_txt
    );
}

sub was_using_frontpage {
    my ($self) = @_;

    my $dir = $self->extractdir();
    return unless -d $dir . '/fp';

    my $fp;
    Cpanel::SafeFind::find(
        {
            'wanted' => sub {
                return unless $File::Find::name =~ m/\.co?nf$/;
                $fp                = 1;
                $File::Find::prune = 1;
                return;
            },
            'no_chdir' => 1,
        },
        "$dir/fp"
    );

    return $fp;
}

sub purge_frontpage_from_htaccess {
    my ( $self, $htaccess_file ) = @_;

    Cpanel::Security::Authz::verify_not_root();

    return unless defined $htaccess_file && -e $htaccess_file;

    my $fh   = IO::Handle->new();
    my $lock = Cpanel::SafeFile::safeopen( $fh, '+<', $htaccess_file );
    if ( !$lock ) {
        $self->warn("Cannot open file: $htaccess_file");
        return 0;
    }

    my @lines = <$fh>;
    seek( $fh, 0, 0 );
    my @buffer;
    foreach my $line (@lines) {

        # before 11.46 all lines with _vti were removed
        #   but the AuthName was preserved...
        #   we are now also removing it
        # remove frontpage comment
        next if $line =~ m/^\#\s+\-FrontPage/ || $line =~ m/^#\s*frontpage/i;
        if ( !@buffer && $line =~ m/^AuthName\s/ ) {

            # also remove the AuthName associate to the _vti AuthUserFile
            push @buffer, $line;
            next;
        }
        if ( $line =~ m/^Auth/ && $line =~ m/_vti/ ) {

            # write the buffer
            if ( scalar @buffer > 1 ) {
                print $fh join( '', @buffer[ 1 .. $#buffer ] );
            }

            # purge the buffer
            @buffer = ();
            next;
        }

        # skip all _vti lines ( except the IndexIgnore one)
        next if $line =~ m/_vti/ && $line !~ m{^\s*IndexIgnore\s}i;
        if (@buffer) {
            push @buffer, $line;
        }
        else {
            print $fh $line;
        }
    }
    print $fh join( '', @buffer[ 0 .. $#buffer ] ) if @buffer;
    truncate( $fh, tell($fh) );
    Cpanel::SafeFile::safeclose( $fh, $lock );

    return 1;
}

1;
