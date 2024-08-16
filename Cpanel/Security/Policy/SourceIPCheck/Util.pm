package Cpanel::Security::Policy::SourceIPCheck::Util;

# cpanel - Cpanel/Security/Policy/SourceIPCheck/Util.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

# The following dependencies must be included by cpsrvd.pl to be available in binary
use Cpanel::JSON         ();
use Cpanel::SafeFile     ();
use Cpanel::SafeDir::MK  ();
use Cpanel::PwCache      ();
use Crypt::Passwd::XS    ();
use Cpanel::Encoder::URI ();
use Cpanel::Logger       ();
use Fcntl                ();
use Cpanel::Locale::Lazy 'lh';

my $logger = Cpanel::Logger->new();

sub NUM_QUESTIONS     { 4; }
sub QUESTIONS_PER_BOX { 7; }

sub validatesecquestions {
    my $questions   = shift;
    my $cpresultref = shift;

    my $qvalid = 1;
    if ( ref $questions eq 'ARRAY' ) {
        $qvalid = !grep { length( $_->[0] ) < 2 || length( $_->[0] ) > 128 || length( $_->[1] ) < 2 || length( $_->[1] ) > 128 } @$questions;
    }
    else {
        for ( 1 .. NUM_QUESTIONS ) {
            my $question = $questions->{ 'q' . $_ . 'ques' };
            my $answer   = lc $questions->{ 'q' . $_ . 'answer' };
            $answer =~ s/\s//g;
            if ( length($question) < 2 || length($question) > 128 || length($answer) < 2 || length($answer) > 128 ) {
                $qvalid = 0;
            }
        }
    }

    if ( !$qvalid ) {
        $cpresultref->{'questions'} = lh()->maketext('Invalid Input');
    }

    return $qvalid;
}

sub resetsecquestions {
    my $sec_policy_dir = shift;
    my $user           = shift;
    $user =~ tr{/}{}d;    # TODO : gwj - need to replace with appropriate scrub functions.

    my $question_file = $sec_policy_dir . '/questions/' . $user;
    return ( !-e $question_file && !-e "$question_file.json" ) || unlink( $question_file, "$question_file.json" );
}

sub complete_questions {
    my $sec_policy_dir  = shift;
    my $questions_in_ar = shift;
    my $user            = shift;
    $user =~ tr{/}{}d;

    my @questions;
    my @to_replace;

    for my $i ( 1 .. NUM_QUESTIONS ) {

        #copy values
        my @qa = $questions_in_ar->[ $i - 1 ] ? @{ $questions_in_ar->[ $i - 1 ] } : ();
        if ( !$qa[1] ) {
            push @to_replace, $i - 1;
        }
        push @questions, \@qa;
    }

    if (@to_replace) {
        my $old_questions = loadsecquestions( $sec_policy_dir, undef, $user );
        if ($old_questions) {
            for my $i (@to_replace) {

                #If the question is empty or it matches the old one,
                #then replace the answer with what was there before.
                #Use a scalar reference so that savesecquestions() knows to
                #leave the digest in place (rather than re-digest'ing it).
                if ( !$questions[$i][0] || ( $questions[$i][0] eq $old_questions->[$i][0] ) ) {
                    $questions[$i] = [ $old_questions->[$i][0], \"$old_questions->[$i][1]" ];
                }
            }
        }
    }

    return wantarray ? @questions : \@questions;
}

sub savesecquestions {
    my $sec_policy_dir = shift;
    my $question_ref   = shift;
    my $user           = shift;
    $user =~ tr{/}{}d;

    my $questions_dir = $sec_policy_dir . '/questions';
    if ( !-e $questions_dir ) {
        Cpanel::SafeDir::MK::safemkdir( $questions_dir, '0711' )
          or $logger->die("Unable to create questions directory: '$questions_dir'\n");
    }

    my @questions;
    if ( ref $question_ref eq 'ARRAY' ) {

        #If the answer is a scalar ref, then leave it in place. (See above.)
        @questions = map { [ $_->[0], ref $_->[1] ? ${ $_->[1] } : digest_answer( $_->[1], $user ), ] } @$question_ref;
    }
    else {
        @questions = map { [ $question_ref->{"q${_}ques"}, digest_answer( $question_ref->{"q${_}answer"}, $user ), ] } ( 1 .. NUM_QUESTIONS );
    }

    my $file = "$questions_dir/$user.json";
    sysopen( my $r_fh, $file, Fcntl::O_WRONLY() | Fcntl::O_CREAT() | Fcntl::O_TRUNC(), 0640 )
      or $logger->die("Cannot create user's questions file '$file': $!\n");
    Cpanel::JSON::DumpFile( $r_fh, \@questions );
    close $r_fh or $logger->die("Cannot close questions file '$file': $!\n");

    # User always needs read privileges (minimum).
    if ( $> == 0 && ( stat($sec_policy_dir) )[4] == 0 ) {
        my $gid = ( Cpanel::PwCache::getpwnam($user) )[3];
        chown 0, $gid, $file;
    }
    return;
}

sub loadsecquestions {
    my ( $sec_policy_dir, $questions_hr, $user ) = @_;
    $user =~ tr{/}{}d;

    my $questions_ar;

    #JSON is the preferred format; check for it first
    my $json_file = "$sec_policy_dir/questions/$user.json";
    if ( -f $json_file && !-z $json_file ) {
        $questions_ar = Cpanel::JSON::LoadFile($json_file);
    }
    else {
        my $file = $sec_policy_dir . '/questions/' . $user;
        return unless -f $file;
        open( my $r_fh, '<', $file ) or $logger->die("Unable to read questions file: '$file'\n");

        $questions_ar = [];
        while ( readline($r_fh) ) {
            chomp();
            my ( $answer, $question ) = split( /:/, $_, 2 );
            $question = Cpanel::Encoder::URI::uri_decode_str($question);
            push @$questions_ar, [ $question, $answer ];
        }
        close($r_fh) or $logger->die("Cannot close questions file: '$file'\n");
    }

    if ($questions_hr) {
        for my $i ( 1 .. scalar @$questions_ar ) {
            @{$questions_hr}{ "secq$i", "seca$i" } = @{ $questions_ar->[ $i - 1 ] };
        }
    }

    #returns a list of question/answer pairs
    return $questions_ar;
}

sub old_style_secquestion {
    my ( $sec_policy_dir, $user ) = @_;
    my $json_file = "$sec_policy_dir/questions/$user.json";
    return -f $json_file ? 0 : 1;
}

sub samplequestions {
    my @questions = (
        lh()->maketext('What is your primary frequent flyer number?'),
        lh()->maketext('What is your library card number?'),
        lh()->maketext('What was your first phone number?'),
        lh()->maketext('What was your first teacher’s name?'),
        lh()->maketext('What is your father’s middle name?'),
        lh()->maketext('What is your maternal grandmother’s first name?'),
        lh()->maketext('In what city was your high school?'),
        lh()->maketext('What was the name of your first boyfriend or girlfriend?'),
        lh()->maketext('What is your maternal grandfather’s first name?'),
        lh()->maketext('In what city were you born (Enter full name of city only)?'),
        lh()->maketext('What was the name of your first pet?'),
        lh()->maketext('What was your high school mascot?'),
        lh()->maketext('How old were you at your wedding (Enter age as digits)?'),
        lh()->maketext('In what year ([asis,YYYY]) did you graduate from high school?'),
        lh()->maketext('In what city did you honeymoon (Enter full name of city only)?'),
        lh()->maketext('What is the first name of the best man/maid of honor at your wedding?'),
        lh()->maketext('What is your paternal grandmother’s first name?'),
        lh()->maketext('What is your mother’s middle name?'),
        lh()->maketext('In what city were you married?'),
        lh()->maketext('In what city is your vacation home?'),
        lh()->maketext('What is the first name of your first child?'),
        lh()->maketext('What is your paternal grandfather’s first name?'),
        lh()->maketext('What is the name of your first employer?'),
        lh()->maketext('When is your wedding anniversary (Enter the full name of month)?'),
        lh()->maketext('What is your paternal grandfather’s first name?'),
        lh()->maketext('What is the first name of the best man/maid of honor at your wedding?'),
        lh()->maketext('In what city was your mother born (Enter full name of city only)?'),
        lh()->maketext('In what city was your father born (Enter full name of city only)?'),
    );
    return wantarray ? @questions : \@questions;
}

sub fetch_ip_list {
    my $sec_policy_dir = shift;
    my $user           = shift;

    my $ip_list_file = $sec_policy_dir . '/iplist/' . $user;
    my ( $ip_list_mtime, $ip_list_size ) = ( stat($ip_list_file) )[ 9, 7 ];
    return 0 if !$ip_list_mtime || !$ip_list_size;

    my $ip_list_cache_file = $sec_policy_dir . '/iplist/' . $user . '.cache';
    my ( $ip_list_cache_mtime, $cache_size ) = ( stat($ip_list_cache_file) )[ 9, 7 ];

    my $now = time();
    my $ipref;
    if (   $cache_size
        && $ip_list_cache_mtime >= $ip_list_mtime
        && $ip_list_cache_mtime < $now ) {
        require Cpanel::SafeStorable;
        eval { $ipref = Cpanel::SafeStorable::retrieve($ip_list_cache_file); };
    }

    if ( !$ipref || ref $ipref ne 'HASH' ) {
        $ipref = {};
        if ( open( my $ip_fh, '<', $ip_list_file ) ) {
            while ( readline($ip_fh) ) {
                chomp();
                $ipref->{$_} = 1;
            }
            close($ip_fh);
        }
    }
    return $ipref;
}

sub deauthorize_ip {
    return authorize_ip( @_, 1 );
}

sub authorize_my_ip {
    my $sec_policy_dir = shift;
    my $user           = shift;
    my $remote_ip      = shift;
    $user =~ tr/\///d;
    if ( !$remote_ip ) {
        Carp::confess("I am missing the users remote ip.  Security Policy requires exec termination.");
    }

    return authorize_ip( $sec_policy_dir, $user, $remote_ip, 0 );
}

sub authorize_ip {
    my $sec_policy_dir = shift;
    my $user           = shift;
    my $match_ip       = shift;
    my $de_auth        = shift;
    $user =~ tr/\///d;

    my $ip_list_dir = "$sec_policy_dir/iplist";
    if ( !-e $ip_list_dir ) {
        Cpanel::SafeDir::MK::safemkdir( $ip_list_dir, '0711' )
          or $logger->die("Unable to create iplist directory: '$ip_list_dir'\n");
    }
    my $ip_list_file       = "$ip_list_dir/$user";
    my $ip_list_cache_file = "$ip_list_dir/$user.cache";

    #we need it 0640
    sysopen( my $r_fh, $ip_list_file, Fcntl::O_WRONLY() | Fcntl::O_CREAT() | Fcntl::O_APPEND(), 0640 );
    close($r_fh);

    my %iplist;
    if ( !-e $ip_list_file ) {
        $logger->warn("Could not find file $ip_list_file");
        return;
    }
    my $iplock = Cpanel::SafeFile::safeopen( \*IPL, '+<', $ip_list_file );
    if ( !$iplock ) {
        $logger->warn("Could not edit $ip_list_file");
        return;
    }
    while ( readline( \*IPL ) ) {
        chomp();
        next if ( $_ eq '' );
        if ( $_ eq $match_ip ) {
            if ($de_auth) {
                next;
            }
            else {
                Cpanel::SafeFile::safeclose( \*IPL, $iplock );
                return;
            }
        }
        $iplist{$_} = 1;
    }

    if ($de_auth) {
        delete $iplist{$match_ip};
        seek( IPL, 0, 0 );
        foreach my $ip ( keys %iplist ) {
            print IPL $ip . "\n";
        }
        truncate( IPL, tell(IPL) );
    }
    else {
        $iplist{$match_ip} = 1;
        print IPL $match_ip . "\n";
    }

    if ( sysopen( my $w_fh, $ip_list_cache_file, Fcntl::O_WRONLY() | Fcntl::O_CREAT() | Fcntl::O_TRUNC(), 0640 ) ) {
        eval { Storable::nstore_fd( \%iplist, $w_fh ); };
        close($w_fh);
    }

    Cpanel::SafeFile::safeclose( \*IPL, $iplock );

    if ( $> == 0 && ( stat($sec_policy_dir) )[4] == 0 ) {
        my $gid = ( Cpanel::PwCache::getpwnam($user) )[3];
        chown 0, $gid, $ip_list_file, $ip_list_cache_file;
    }
    return 1;
}

sub has_security_questions {
    my $sec_policy_dir = shift;
    my $user           = shift;
    $user =~ tr/\///d;
    if ( -e "$sec_policy_dir/questions/$user.json" ) {
        return 1;
    }
    elsif ( -e "$sec_policy_dir/questions/$user" ) {
        return 1;
    }
    return 0;
}

sub digest_user {
    my ($user) = @_;

    return '' if !defined $user || $user eq '';

    $user = Crypt::Passwd::XS::unix_md5_crypt( $user, '' );

    # Strip off the $1$$ from the front of the crypted string.
    return substr( $user, 4 );
}

sub digest_answer {
    my ( $answer, $user ) = @_;

    return '' if !defined $user || $user eq '' || !defined $answer || $answer eq '';

    my $digest = Crypt::Passwd::XS::unix_md5_crypt( $answer, $user );

    # Strip off the $1$$ from the front of the crypted string.
    $digest =~ s/^\$1\$[^\$]+\$//;
    return $digest;
}

1;
