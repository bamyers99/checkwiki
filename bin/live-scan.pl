#! /usr/bin/env perl
#
############################################################################
###
### FILE:   live_scan.pl
### USAGE:  live_scan.pl -c database.cfg
###
### DESCRIPTION: Retrieves new revised articles from Wikipedia and stores
###              the articles in a database.  Checkwiki.pl can retrieve
###              the articles for processing.
###
### AUTHOR:  Bryan White
### Licence: GPL3
###
############################################################################

use strict;
use warnings;

use DBI;
use Getopt::Long
  qw(GetOptionsFromString :config bundling no_auto_abbrev no_ignore_case);

use MediaWiki::API;
use MediaWiki::Bot;

binmode( STDOUT, ':encoding(UTF-8)' );

my $dbh;

my %Limit       = ();
my @ProjectList = qw/ enwiki dewiki eswiki frwiki arwiki cswiki plwiki /;
my @Titles;

open_db();
numberofarticles();

foreach my $item (@ProjectList) {
    retrieveArticles($item);
    insert_db($item);
    undef(@Titles);
}

close_db();

###########################################################################
###
############################################################################

sub numberofarticles {

    %Limit = (
        enwiki => 500,
        dewiki => 300,
        eswiki => 300,
        frwiki => 300,
        arwiki => 200,
        cswiki => 200,
        plwiki => 200,
    );

    return ();
}

###########################################################################
##  RETRIVE ARTICLES FROM WIKIPEDIA
###########################################################################

sub retrieveArticles {
    my ($project)      = @_;
    my $page_namespace = 0;
    my $servername     = $project;

    # Calculate server name.
    if (
        !(
               $servername =~ s/^nds_nlwiki$/nds-nl.wikipedia.org/
            || $servername =~ s/^([[:lower:]]+)wiki$/$1.wikipedia.org/
            || $servername =~ s/^([[:lower:]]+)wikisource$/$1.wikisource.org/
            || $servername =~ s/^([[:lower:]]+)wikiversity$/$1.wikiversity.org/
            || $servername =~ s/^([[:lower:]]+)wiktionary$/$1.wiktionary.org/
            || $servername =~ s/^([[:lower:]]+)wikivoyage$/$1.wikivoyage.org/
        )
      )
    {
        die( 'Could not calculate server name for ' . $servername . "\n" );
    }

    my $bot = MediaWiki::Bot->new(
        {
            assert   => 'bot',
            protocol => 'https',
            host     => $servername,
            operator => 'CheckWiki',
        }
    );
    
    my $maxcalls = 1;
    if ($project eq 'enwiki' or $project eq 'dewiki') {$maxcalls = 2;} # Changes are getting missed, so do 2 queries

    my @rc = $bot->recentchanges(
        { ns => $page_namespace, limit => $Limit{$project} }, { max => $maxcalls } );
    foreach my $hashref (@rc) {
        push( @Titles, $hashref->{title} );
    }

    return ();
}

###########################################################################
## INSERT THE ARTICLE'S TITLES INTO DATABASE
###########################################################################

sub insert_db {
    my ($project) = @_;
    my $null = undef;
    my $sth = $dbh->prepare(
        'INSERT IGNORE INTO cw_new (Project, Title) VALUES (?, ?);')
      or die "Can not prepare statement: $DBI::errstr\n";

    foreach my $title (@Titles) {
        $sth->execute( $project, $title )
          or die "Cannot execute: $sth->errstr\n";
    }

    return ();
}

###########################################################################
## OPEN DATABASE
###########################################################################

sub open_db {
    my $DbName      = q{};
    my $DbServer    = q{};
    my $DbUsername  = q{};
    my $DbPassword  = q{};
    my $config_name = q{};

    GetOptions(
        'database|D=s' => \$DbName,
        'host|h=s'     => \$DbServer,
        'password=s'   => \$DbPassword,
        'user|u=s'     => \$DbUsername,
        'config|c=s'   => \$config_name,
    );

    if ( defined $config_name ) {
        open( my $file, '<:encoding(UTF-8)', $config_name )
          or die 'Could not open file ' . $config_name . "\n";
        while ( my $line = <$file> ) {
            chomp($line);
            my @words = ( split / /, $line );
            $DbName     = $words[1] if ( $words[0] =~ /--database/ );
            $DbUsername = $words[1] if ( $words[0] =~ /--user/ );
            $DbPassword = $words[1] if ( $words[0] =~ /--password/ );
            $DbServer   = $words[1] if ( $words[0] =~ /--host/ );
        }
        close($file)
          or die 'Could not close file ' . $config_name . "\n";
    }
    else {
        die("No config file entered, for example: -c checkwiki.cfg\n");
    }

    $dbh = DBI->connect(
        'DBI:mysql:'
          . $DbName
          . ( defined($DbServer) ? ':host=' . $DbServer : q{} ),
        $DbUsername,
        $DbPassword,
        {
            mysql_enable_utf8 => 1,
        }
    ) or die( 'Could not connect to database:' . DBI::errstr() . "\n" );

    return ();
}

###########################################################################
## CLOSE DATABASE
###########################################################################

sub close_db {

    $dbh->disconnect();

    return ();
}