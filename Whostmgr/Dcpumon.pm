package Whostmgr::Dcpumon;

# cpanel - Whostmgr/Dcpumon.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#THIS MODULE IS A COPY OF /usr/local/cpanel/bin/dcpumonview.pm, MODIFIED
#FOR USE AS A MODULE.

use strict;

use Cpanel::ArrayFunc::Uniq    ();
use Cpanel::Validate::Username ();
use Cpanel::Debug              ();
use Cpanel::FileUtils::Write   ();
use Cpanel::LoadFile           ();
use Cpanel::StringFunc::Trim   ();

my @months = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);

my $processes_to_kill_file = '/var/cpanel/killproc.conf';
my $trusted_users_file     = '/var/cpanel/trustedusers';
my $symbol_files_directory = '/usr/local/cpanel/etc/sym';

my $cache;

sub _get {
    my $filename = shift;

    return if !-e $filename;

    my $text = Cpanel::LoadFile::loadfile($filename);
    if ( !defined($text) ) {
        Cpanel::Debug::log_warn("Unable to read $filename: $!");
        return;
    }

    #Trim leading/trailing space from each line, reject empty strings.
    return grep { length } split m{\s*[\r\n]+\s*}, Cpanel::StringFunc::Trim::ws_trim($text);
}

sub _save {
    my $filename = shift;
    my $text     = join q{}, map { "$_\n" } @_;
    if ( !Cpanel::FileUtils::Write::overwrite_no_exceptions( $filename, $text, 0644 ) ) {
        Cpanel::Debug::log_warn("Unable to write $filename: $!");
        return;
    }

    return 1;
}

sub get_processes_to_kill {
    return _get($processes_to_kill_file);
}

sub save_processes_to_kill {
    return _save( $processes_to_kill_file, sort( Cpanel::ArrayFunc::Uniq::uniq(@_) ) );
}

sub get_trusted_users {
    return _get($trusted_users_file);
}

sub save_trusted_users {
    my @invalid = grep { !Cpanel::Validate::Username::is_valid($_) } @_;
    if ( scalar @invalid ) {
        Cpanel::Debug::log_warn( "Invalid trusted users submitted: ", join( ', ', @invalid ) );
        return;
    }

    return _save( $trusted_users_file, sort( Cpanel::ArrayFunc::Uniq::uniq(@_) ) );
}

sub remove_trusted_user {
    my ($user_to_remove) = @_;

    my @trusted_users = get_trusted_users();

    my @trusted_users_to_save = grep { $_ ne $user_to_remove } @trusted_users;

    # Only save the file if we removed the user from the list
    # No need to touch the file if the user was never in it
    if ( scalar @trusted_users > scalar @trusted_users_to_save ) {
        return _save( $trusted_users_file, @trusted_users_to_save );
    }

    return 1;
}

sub get_symbol_filenames {
    my @files;
    if ( opendir my $symdh, $symbol_files_directory ) {
        while ( my $file = readdir $symdh ) {
            next if $file =~ m{\A\.};
            $file =~ s{\.sym\z}{}g;
            push @files, $file;
        }
        closedir $symdh;
    }
    else {
        Cpanel::Debug::log_warn("Could not open $symbol_files_directory: $!");
    }

    return @files;
}

sub get_cpu_data {
    return $cache if $cache;

    my @cpu_data;
    my ( $year, $month, $day ) = @_;

    open my $cpudata, '<', "/var/log/dcpumon/$year/$months[$month-1]/$day";
    <$cpudata>;    #totaltime
    <$cpudata>;    #lasttime

    while (<$cpudata>) {
        s/\n//g;
        my (
            $user,
            $cpu,
            $mem,
            $mysql,
            $topcpu1,
            $topcpuname1,
            $topcpu2,
            $topcpuname2,
            $topcpu3,
            $topcpuname3
        ) = split( /=/, $_ );

        my @top_data = (
            { 'cpu' => $topcpu1, 'name' => $topcpuname1 },
            { 'cpu' => $topcpu2, 'name' => $topcpuname2 },
            { 'cpu' => $topcpu3, 'name' => $topcpuname3 },
        );
        push @cpu_data,
          {
            'user'  => $user,
            'cpu'   => $cpu,
            'mem'   => $mem,
            'mysql' => $mysql,
            'top'   => \@top_data,
          };

    }
    close($cpudata);

    return ( $cache = \@cpu_data );
}

1;
