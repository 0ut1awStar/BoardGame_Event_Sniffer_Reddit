# Script to scrape various subreddits and post in a discord webhook any that seem to be related to a board game meetup
# .5
# 10-07-23
# Andrew Lund

Clear-Variable logfile -ErrorAction SilentlyContinue

$KeyPath = "C:\temp"
$logFilePath = "C:\temp\boardgameEvents"

$pathExists = Test-Path -LiteralPath "$logFilePath"
if ($pathExists -eq $false) { mkdir "$logFilePath" }
$logExists = Test-Path -LiteralPath "$logFilePath\Log.txt"
if ($logExists -eq $false) { Out-File "$logFilePath\Log.txt"}

$logFile = Get-Content -Path "$($logFilePath)\Log.txt"

$urlBase = "https://old.reddit.com/r/"
$subredditArrayToCheck = @("twincitiessocial","twincitiesgeeks")

# Grab current location of script
$currentDirectory = $PSScriptRoot
# full url of discord webhook should be in secrets.txt
$discordWebHook = cat "$currentDirectory\secrets.txt"




$suburbList = "South St Paul","West St Paul","Andover","Anoka","Bethel","Blaine","Columbia Heights","Circle Pines","Coon Rapids","East Bethel","Fridley","Hilltop","Ham Lake","Lino Lakes","Oak Grove","Ramsey","St. Francis","Spring Lake Park","Carver","Chaska","Chanhassen","Victoria","Apple Valley","Burnsville","Eagan","Farmington","Hampton","Hastings","Inver Grove Heights","Lakeville","Lilydale","Mendota","Mendota Heights","New Trier","Rosemount","South St. Paul","Sunfish Lake","Vermillion","West St. Paul","Bloomington","Brooklyn Center","Brooklyn Park","Champlin","Corcoran","Crystal","Dayton","Eden Prairie","Edina","Excelsior","Golden Valley","Greenfield","Greenwood","Hopkins","Independence","Long Lake","Loretto","Maple Grove","Medicine Lake","Medina","Minnetonka","Minnetonka Beach","Minnetrista","Mound","New Hope","Orono","Osseo","Plymouth","Richfield","Robbinsdale","Rogers","St. Anthony","St. Bonifacius","St. Louis Park","Shorewood","Spring Park","Tonka Bay","Wayzata","Woodland","Arden Hills","Falcon Heights","Gem Lake","Lauderdale","Little Canada","Maplewood","Mounds View","New Brighton","North Oaks","North St. Paul","Roseville","Shoreview","St. Anthony","Vadnais Heights","White Bear Lake","Belle Plaine","Elko New Market","Jordan","New Prague","Prior Lake","Savage","Shakopee","Afton","Birchwood Village","Cottage Grove","Dellwood","Forest Lake","Grant","Hugo","Lake Elmo","Lakeland","Minneapolis","Lakeland Shores","Lake St. Croix Beach","Landfall","Mahtomedi","Marine on St. Croix","Newport","Oakdale","Pine Springs","St. Marys Point","St. Paul Park","Stillwater","Willernie","Woodbury","Albertville","Buffalo","Delano","Hanover","Monticello","St. Michael"
$gameStoreList = "Fantasy Flight","Gamezenter","Dreamers","Gaming Goat","Tower Games","Galaxy Games","Red 6 Games","NerdinOut","Heroic Goods","Steamship Games","Dumpster Cat games","Level Up","Village Games","Lodestone","Phoenix","1Up","Fire and Nice","Fire & Nice"




Clear-Variable output, subredditoutputcombined -ErrorAction SilentlyContinue

# Gather 2 pages worth of links
# INPUT: an array of subreddits to check, each item in array being a string eg. "twincitiessocial"
# OUTPUT: Large json data object of posts/links in subreddits
function gatherSubredditPosts
    {
        param($subredditList)
        Clear-Variable subredditOutputCombined -ErrorAction SilentlyContinue

        Foreach ($subreddit in $subredditList)
            {
                Clear-Variable collectionObject -ErrorAction SilentlyContinue
                [array]$jsonCollectionObject = @()


                # Find link to "second" page of subreddit
                $findPaginationButtonForNext25 = Invoke-WebRequest -uri "$($urlBase)$($subreddit)" -UseBasicParsing
                $urlForNextPage = $(($findPaginationButtonForNext25.links | WHERE {$_.rel -eq 'nofollow next'}).href)
                $urlForNextPageWithJSONAttribute = $urlForNextPage.replace('/?count','/.json?count')

                # Collect JSON data from subreddit
                $jsonCollectionObject += Invoke-WebRequest -uri "$($urlBase)$($subreddit).json" -UseBasicParsing

                $jsonCollectionObject += Invoke-WebRequest -uri "$($urlForNextPageWithJSONAttribute)" -UseBasicParsing

                # add to uber object
                $subredditOutputCombined += $jsonCollectionObject

            }

        return($subredditOutputCombined)
    }

# Check each one via regex if it's board game related
# if board game related open link/post and regex the summary for more info
# INPUT: uber object from "gatherSubredditPosts" function/output
# OUTPUT: Items that are board game releated in array/object

function findBoardGameRelatedPosts
    {
        param($allPostsFromSubreddits)
        
        # Regex to match against the titles
        $boardGamePosts = ($allPostsFromSubreddits.content | ConvertFrom-Json).data.children.data | Where {$_.title -match "(oard.ames|oard\s.ames|oard.ame|oard\s.ame|oard\s.aming)"}

        return($boardGamePosts)
    }



# Check if this has been posted already (check the save file)
# INPUT: boardgame posts json object
# OUTPUT: None
function isThisPostANewEvent
    {
        param($boardGameJSONObjects)
        # Check each post, is it new?

        foreach ($post in $boardGameJSONObjects)
            {
            # If we don't find the post id already in log continue (AKA it's a new post)
                if (!($logFile -contains "$($Post.id)"))
                    {
                    Clear-Variable likelysuburb, likelygameshop -ErrorAction SilentlyContinue
                        # Compare the summary text to the list of game shops and suburbs to take a guess as to where it is
                        $likelySuburb = (CountItemsInString -InputString $post.selftext -Items $suburbList | where {$_.count -gt 0})[0].item.tostring()
                        $likelyGameShop = (CountItemsInString -InputString $post.selftext -Items $gameStoreList | where {$_.count -gt 0})[0].item.tostring()

                        # Generate the body hashtable and conver to JSON to send to webhook
                        $jsonBody = @{
                            embeds = @(
                                @{
                                    title = "$($Post.Title)"
                                    url = "$($Post.Url)"
                                    color = 8913109
                                    footer = ""
                                    author = @{
                                                name = "Posted by: $($Post.Author)"
                                                url = "https://old.reddit.com/u/$($Post.Author)"
                                            }
                                    fields = @( 
                                            @{
                                                name = "Store (Estimate)"
                                                value = "$($likelyGameShop)"
                                            },
                                            @{
                                                name = "City (Estimate)"
                                                value = "$($likelySuburb)"

                                            },
                                            @{
                                             # Each of these field values is limited to 1024 characters
                                                name = "Post Text"
                                                value =$($Post.Selftext[0..1020] -join "") + "..."

                                        })


                                }
                            )


                        } | ConvertTo-Json -Depth 100

                        Foreach ($webhook in $discordWebHook)
                            {
                                Invoke-RestMethod -uri $($webhook) -Body $jsonBody -Method Post -ContentType "application/json"
                            }

                        # Then save the id so that it isn't reported again
                        # Add the videoID to the Log file
                        $Post.id | Out-File -LiteralPath "$logFilePath\Log.txt" -Append
                    }
            }



    }


function CountItemsInString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [string]$InputString,
        [Parameter(Mandatory=$true)]
        [string[]]$Items
    )

    # Create an array to store the counts of each item
    $counts = @()

    # Loop through each item
    foreach ($item in $Items) {
        # Count how many times the item appears in the input string
        $count = ([regex]::Matches($InputString, [regex]::Escape($item)) | Measure-Object).Count

        # Add the item and count to the array
        $counts += [pscustomobject]@{
            Item = $item
            Count = $count
        }
    }

    # Output the array
    return $counts
}




$output = gatherSubredditPosts -subredditList $subredditArrayToCheck

$matchedPosts = findBoardGameRelatedPosts -allPostsFromSubreddits $output

isThisPostANewEvent -boardGameJSONObjects $matchedPosts