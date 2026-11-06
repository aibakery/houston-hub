-- Authored native Graph requests; fixtures execute every example.
return json.decode([====[
{
	"createComment": [
		{
			"message": "Thank you for your support!",
			"object": "101_456"
		}
	],
	"createInstagramContainer": [
		{
			"alt_text": "An illustrated mountain landscape",
			"caption": "A new illustration.",
			"ig_user": "178900000000001",
			"image_url": "https://example.com/print.jpg",
			"user_tags": [
				{
					"username": "example_artist",
					"x": 0.5,
					"y": 0.5
				}
			]
		},
		{
			"caption": "Two new illustrations",
			"children": [
				"179000000000002",
				"179000000000003"
			],
			"ig_user": "178900000000001",
			"media_type": "CAROUSEL"
		},
		{
			"ig_user": "178900000000001",
			"media_type": "REELS",
			"share_to_feed": true,
			"video_url": "https://example.com/studio.mp4"
		}
	],
	"createInstagramReply": [
		{
			"comment": "179000000000001",
			"message": "Thank you!"
		}
	],
	"createPost": [
		{
			"link": "https://example.com/prints",
			"message": "A new print is available."
		}
	],
	"deleteObject": [
		{
			"id": "101_456"
		}
	],
	"getInsights": [
		{
			"metric": [
				"page_media_view",
				"page_post_engagements"
			],
			"object": "me",
			"period": "day",
			"since": "2026-11-01",
			"until": "2026-11-07"
		}
	],
	"getInstagramAccount": [
		{
			"ig_user": "178900000000001"
		}
	],
	"getInstagramPublishingLimit": [
		{
			"ig_user": "178900000000001"
		}
	],
	"getObject": [
		{
			"fields": "id,message,permalink_url",
			"id": "101_456"
		}
	],
	"getPage": [
		{
			"fields": "id,name,instagram_business_account{id,username}"
		}
	],
	"listComments": [
		{
			"filter": "toplevel",
			"limit": 20,
			"object": "101_456",
			"order": "chronological",
			"summary": true
		},
		{
			"next": "opaque-next-listComments"
		}
	],
	"listConversations": [
		{
			"limit": 20,
			"platform": "messenger"
		}
	],
	"listFeed": [
		{
			"limit": 20,
			"since": "2026-11-01",
			"until": "2026-11-30"
		}
	],
	"listHashtagRecentMedia": [
		{
			"hashtag": "178400000000001",
			"limit": 20,
			"user_id": "178900000000001"
		}
	],
	"listHashtagTopMedia": [
		{
			"hashtag": "178400000000001",
			"limit": 20,
			"user_id": "178900000000001"
		}
	],
	"listInstagramChildren": [
		{
			"media": "180000000000001"
		}
	],
	"listInstagramComments": [
		{
			"limit": 20,
			"media": "180000000000001"
		}
	],
	"listInstagramMedia": [
		{
			"ig_user": "178900000000001",
			"limit": 20
		}
	],
	"listInstagramReplies": [
		{
			"comment": "179000000000001"
		}
	],
	"listInstagramStories": [
		{
			"ig_user": "178900000000001"
		}
	],
	"listInstagramTags": [
		{
			"ig_user": "178900000000001"
		}
	],
	"listMessages": [
		{
			"conversation": "t_123",
			"limit": 20
		}
	],
	"listPhotos": [
		{
			"limit": 20,
			"type": "uploaded"
		}
	],
	"listPublishedPosts": [
		{
			"include_hidden": false,
			"limit": 20
		}
	],
	"listRatings": [
		{}
	],
	"listReactions": [
		{
			"limit": 20,
			"object": "101_456",
			"summary": "total_count",
			"type": "LIKE"
		}
	],
	"listReels": [
		{}
	],
	"listScheduledPosts": [
		{}
	],
	"listTaggedPosts": [
		{}
	],
	"listVideos": [
		{}
	],
	"publishInstagramMedia": [
		{
			"creation_id": "179000000000002",
			"ig_user": "178900000000001"
		}
	],
	"searchInstagramHashtag": [
		{
			"q": "illustration",
			"user_id": "178900000000001"
		}
	],
	"sendInstagramPrivateReply": [
		{
			"ig_user": "178900000000001",
			"message": {
				"text": "Thanks for your interest. Here are the details."
			},
			"recipient": {
				"comment_id": "179000000000001"
			}
		}
	],
	"sendMessage": [
		{
			"message": {
				"text": "Thanks for your message!"
			},
			"messaging_type": "RESPONSE",
			"recipient": {
				"id": "123456789012345"
			}
		},
		{
			"recipient": {
				"id": "123456789012345"
			},
			"sender_action": "typing_on"
		},
		{
			"message": {
				"attachment": {
					"payload": {
						"is_reusable": true,
						"url": "https://example.com/print.jpg"
					},
					"type": "image"
				}
			},
			"messaging_type": "RESPONSE",
			"recipient": {
				"id": "123456789012345"
			}
		}
	],
	"updateComment": [
		{
			"comment": "179000000000001",
			"is_hidden": true
		}
	],
	"updateInstagramMedia": [
		{
			"comment_enabled": false,
			"media": "180000000000001"
		}
	],
	"updatePost": [
		{
			"is_pinned": true,
			"message": "Our new print is now available.",
			"post": "101_456"
		}
	],
	"uploadPhoto": [
		{
			"caption": "New art print",
			"published": false,
			"url": "https://example.com/print.jpg"
		},
		{
			"caption": "Art print",
			"path": "photo.jpg",
			"published": false
		}
	],
	"uploadVideo": [
		{
			"description": "Behind the scenes",
			"file_url": "https://example.com/studio.mp4",
			"published": false,
			"title": "Studio tour"
		},
		{
			"path": "video.mp4",
			"published": false,
			"title": "Studio tour"
		}
	]
}
]====])
