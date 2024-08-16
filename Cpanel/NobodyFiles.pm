package Cpanel::NobodyFiles;

# cpanel - Cpanel/NobodyFiles.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Exception ();
use Cpanel::Fcntl     ();
use Cpanel::ForkSync  ();
use Cpanel::PwCache   ();
use Cpanel::SafeSync  ();

my $NULL_CHR = chr(0);

sub notate_nobodyfiles {
    my ( $source_dir, $output_fh ) = @_;

    my $source_dir_uid = ( stat($source_dir) )[4];

    my $nfl_ref = Cpanel::SafeSync::find_uid_files( $source_dir, ['nobody'], $source_dir_uid );

    return write_nobodyfiles_to_fh( $source_dir, $output_fh, $nfl_ref );
}

sub write_nobodyfiles_to_fh {
    my ( $source_dir, $output_fh, $nfl_ref ) = @_;
    foreach my $file ( keys %$nfl_ref ) {
        chomp($file);
        $file =~ s/^\Q$source_dir\E\/?//g;
        print {$output_fh} $file . "\n";
    }
    return;
}

sub chown_nobodyfiles {
    my ( $target, $input_fh, $user ) = @_;

    my ( $nobody_uid, $nobody_gid ) = ( Cpanel::PwCache::getpwnam('nobody') )[ 2, 3 ];
    my $user_uid = ( Cpanel::PwCache::getpwnam($user) )[2];

    my $locale        = _locale();                                                   # must be called before chroot()
    my $sysopen_flags = Cpanel::Fcntl::or_flags(qw( O_RDONLY O_NOFOLLOW O_EXCL ));

    my $run = Cpanel::ForkSync->new(
        sub {
            local $!;
            chroot($target) || die Cpanel::Exception::create( 'IO::ChrootError', [ error => $!, path => $target ] );
            chdir('/')      || die Cpanel::Exception::create( 'IO::ChdirError',  [ error => $!, path => $target ] );

            while ( my $file = readline($input_fh) ) {
                next if ( $file =~ m{\.\.\/} );
                next if ( $file =~ m{$NULL_CHR} );
                chomp $file;
                my $chownfile = $file;
                next if ( !-f $chownfile && !-d _ );

                sysopen( my $fh, $chownfile, $sysopen_flags ) or do {
                    warn( _locale()->maketext( 'Failed to change ownership on “[_1]”: [_2]', $chownfile, $! ) );
                    next;
                };

                # stat() is ok, sysopen() will fail if the file is a symlink due to O_NOFOLLOW
                my ( $file_links, $file_uid ) = ( stat($fh) )[ 3, 4 ];

                if ( my $file_links > 1 ) {
                    warn( _locale()->maketext( 'The system did not change ownership on the file “[_1]”: multiply-linked file (number of links: [_2])', $chownfile, $file_links ) );
                    next;
                }

                if ( $file_uid != $user_uid ) {
                    warn( _locale()->maketext( 'The system did not change the ownership on “[_1]”: the file’s [asis,UID] did not match the user’s [asis,UID]', $chownfile ) );
                    next;
                }

                chown( $nobody_uid, $nobody_gid, $fh ) or do {
                    warn( _locale()->maketext( 'The system failed to change ownership of “[_1]” to “[_2]” because of an error: [_3]', $chownfile, 'nobody', $! ) );
                };

                close($fh);
                $! = undef;
            }
            if ($!) {
                warn( _locale()->maketext( 'The system failed to read from a file handle because of an error: [_1]', $! ) );
            }

            # Case 154569: DBI segfaults in global destruction if this variable
            # refers to an open handle.
            $Cpanel::MysqlUtils::Connect::dbh_singleton = undef;

            return;
        }
    );

    if ( !$run ) {
        die Cpanel::Exception->create_raw( _locale()->maketext('The system failed to create a child process to chown files to the nobody user.') );
    }
    elsif ( $run->had_error() ) {
        die Cpanel::Exception->create_raw( $run->exception() || $run->autopsy() );
    }

    return 1;
}

my $locale;

sub _locale {
    require Cpanel::Locale;
    return ( $locale ||= Cpanel::Locale->get_handle() );
}

1;
