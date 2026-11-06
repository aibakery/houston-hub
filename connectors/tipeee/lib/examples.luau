-- Authored native request examples; fixtures execute every example.
return json.decode([====[
{
	"blockTipper": [
		{
			"data": {
				"status": "TIP_BANNED",
				"target": 42
			},
			"username": "ana"
		}
	],
	"checkProjectSlug": [
		{
			"slug": "my-art"
		}
	],
	"cloneReward": [
		{
			"project": "my-art",
			"reward": 7
		}
	],
	"closeProject": [
		{
			"data": {
				"token": "012345"
			},
			"project": "my-art"
		}
	],
	"configureAlertsWidget": [
		{
			"data": {
				"show_message": true,
				"sound": {
					"static_id": 1,
					"type": "static",
					"volume": 0.5
				},
				"text_color_var": "#ffffff",
				"theme": "default"
			},
			"project": "my-art"
		}
	],
	"configureGoalsWidget": [
		{
			"data": {
				"goal_amount": 1000,
				"initial_amount": 0,
				"name": "New tablet",
				"reset": false
			},
			"project": "my-art"
		}
	],
	"configureLastsWidget": [
		{
			"data": {
				"events_count": 5,
				"show_amount": true,
				"show_title": true
			},
			"project": "my-art"
		}
	],
	"configureTotalsWidget": [
		{
			"data": {
				"show_amount": true,
				"show_project_avatar": true
			},
			"project": "my-art"
		}
	],
	"createComment": [
		{
			"data": {
				"body": "Thank you for the update!",
				"parent": 8
			},
			"thread": "news-update"
		},
		{
			"data": {
				"body": "Thank you!"
			},
			"thread": "news-update"
		}
	],
	"createGoal": [
		{
			"data": {
				"amount": 1000,
				"translations": {
					"en": {
						"description": "\u003cp\u003eA new drawing tablet.\u003c/p\u003e",
						"name": "Studio equipment"
					}
				}
			},
			"project": "my-art"
		}
	],
	"createNews": [
		{
			"data": {
				"contentv2": {
					"translations": {
						"en": {
							"html": "\u003cp\u003eA new illustration is coming.\u003c/p\u003e"
						}
					}
				},
				"draft": true,
				"name": "Studio update"
			},
			"project": "my-art"
		}
	],
	"createOneOffProject": [
		{
			"data": {
				"categories": [
					1,
					3
				],
				"lang": "en",
				"slug": "my-art",
				"translations": {
					"en": {
						"name": "My art"
					}
				}
			}
		}
	],
	"createProject": [
		{
			"data": {
				"categories": [
					1,
					3
				],
				"lang": "en",
				"slug": "my-art",
				"translations": {
					"en": {
						"name": "My art"
					}
				}
			}
		}
	],
	"createReward": [
		{
			"data": {
				"modules": {
					"stock": {
						"_is_Activate": true,
						"available": {
							"quantity": 20,
							"unlimited": false
						}
					}
				},
				"price": 10,
				"translations": {
					"en": {
						"description_v2": "\u003cp\u003eA monthly digital print.\u003c/p\u003e",
						"name": "Digital print"
					}
				}
			},
			"project": "my-art"
		}
	],
	"deleteComment": [
		{
			"comment": 7,
			"thread": "news-update"
		}
	],
	"deleteGoal": [
		{
			"goal": 7,
			"project": "my-art"
		}
	],
	"deleteNews": [
		{
			"news": 7,
			"project": "my-art"
		}
	],
	"deleteThread": [
		{
			"threadToUser": 7
		}
	],
	"disconnectDiscord": [
		{
			"project": "my-art"
		}
	],
	"downloadMedia": [
		{
			"media": "media-demo",
			"mode": "original",
			"output": "example-downloadMedia.bin"
		}
	],
	"downloadPaymentBill": [
		{
			"document": "payment-7.pdf",
			"output": "example-downloadPaymentBill.bin"
		}
	],
	"downloadPaymentTips": [
		{
			"document": "payment-7.pdf",
			"output": "example-downloadPaymentTips.bin"
		}
	],
	"downloadPayments": [
		{
			"output": "example-downloadPayments.bin",
			"report": "my-art_2026.csv"
		}
	],
	"downloadPrivateMedia": [
		{
			"media": "media-demo",
			"output": "example-downloadPrivateMedia.bin"
		}
	],
	"downloadTippers": [
		{
			"output": "example-downloadTippers.bin",
			"report": "2026-11.csv"
		}
	],
	"emailTippersExport": [
		{
			"report": "2026-11.csv"
		}
	],
	"enableStreaming": [
		{
			"project": "my-art"
		}
	],
	"findOrCreateThread": [
		{
			"data": {
				"project": 7,
				"receiver": 42
			},
			"username": "ana"
		}
	],
	"followThread": [
		{
			"threadToUser": 7
		}
	],
	"getCampaignRewardStats": [
		{
			"campaign": 7,
			"project": "my-art"
		}
	],
	"getCloseDate": [
		{
			"project": "my-art"
		}
	],
	"getDiscordGuild": [
		{
			"project": "my-art"
		}
	],
	"getInboxThread": [
		{
			"threadToUser": 19
		}
	],
	"getMe": [
		{}
	],
	"getMessageSupporter": [
		{
			"project": "my-art",
			"user": 42
		}
	],
	"getNews": [
		{
			"news": 7,
			"project": "my-art"
		}
	],
	"getPayoutState": [
		{
			"project": "my-art"
		}
	],
	"getProject": [
		{
			"project": "my-art"
		}
	],
	"getRecurringIndicators": [
		{
			"project": "my-art"
		}
	],
	"getReward": [
		{
			"project": "my-art",
			"reward": 7
		}
	],
	"getRewardTemplate": [
		{
			"project": "my-art"
		}
	],
	"getStatistics": [
		{
			"endDate": "2026-11-30",
			"project": "my-art",
			"startDate": "2026-11-01",
			"timeUnit": "DAY",
			"type": "VISITOR_NUMBER"
		}
	],
	"getUnreadMessages": [
		{
			"username": "ana"
		}
	],
	"getWidgetGoal": [
		{
			"date": "2026-11-01",
			"project": "my-art"
		}
	],
	"getWidgets": [
		{
			"project": "my-art"
		}
	],
	"listCampaignRewards": [
		{
			"campaign": 7,
			"project": "my-art"
		}
	],
	"listCampaigns": [
		{
			"project": "my-art"
		}
	],
	"listCategories": [
		{}
	],
	"listComments": [
		{
			"direction": "next",
			"perPage": 10,
			"thread": "news-update",
			"token": "older-cursor"
		}
	],
	"listInboxProjects": [
		{
			"username": "ana"
		}
	],
	"listInboxThreads": [
		{
			"page": 1,
			"project": 7,
			"username": "ana"
		}
	],
	"listMessages": [
		{
			"threadToUser": 19,
			"token": "older-cursor"
		}
	],
	"listNews": [
		{
			"page": 1,
			"perPage": 10,
			"project": "my-art",
			"statusFilter": "draft"
		}
	],
	"listNewsDrafts": [
		{
			"project": "my-art"
		}
	],
	"listPayments": [
		{
			"project": "my-art",
			"year": "2026"
		}
	],
	"listProjectFeed": [
		{
			"perPage": 15,
			"project": "my-art",
			"read": "false",
			"type": "ALL",
			"user": "ana"
		}
	],
	"listProjects": [
		{
			"lang": "en",
			"mode": "search",
			"page": 1,
			"perPage": 20,
			"q": "art"
		}
	],
	"listRewards": [
		{
			"page": 1,
			"perPage": 12,
			"priceMax": 20,
			"priceMin": 5,
			"project": "my-art"
		}
	],
	"listSupportMessages": [
		{
			"page": 1,
			"perPage": 10,
			"project": "my-art"
		}
	],
	"listTippers": [
		{
			"campaign": 7,
			"noReward": 0,
			"page": 1,
			"perPage": 100,
			"project": "my-art"
		}
	],
	"listTopTippers": [
		{
			"page": 1,
			"perPage": 20,
			"project": "my-art"
		}
	],
	"lockThread": [
		{
			"threadToUser": 7
		}
	],
	"markNotificationRead": [
		{
			"notification": 7,
			"user": "ana"
		}
	],
	"markProjectFeedRead": [
		{
			"project": "my-art",
			"user": "ana"
		}
	],
	"prepareProjectPublication": [
		{
			"project": "my-art"
		}
	],
	"publishProject": [
		{
			"data": {
				"adyen": "on",
				"hyperwallet": "on",
				"tipeee": "on"
			},
			"project": "my-art"
		}
	],
	"renameThread": [
		{
			"data": {
				"title": "Art print questions"
			},
			"threadToUser": 7
		}
	],
	"replayStreamAlert": [
		{
			"subscription": 7
		}
	],
	"requestPayout": [
		{
			"project": "my-art"
		}
	],
	"requestProjectClosureCode": [
		{
			"project": "my-art"
		}
	],
	"searchMessageTippers": [
		{
			"page": 1,
			"project": "my-art",
			"q": "Ana"
		}
	],
	"sendMessage": [
		{
			"data": {
				"action": "RESPONSE",
				"content": "Thank you for your support!",
				"thread": 4
			}
		},
		{
			"data": {
				"action": "CREATE",
				"attachments": [],
				"content": "A studio update",
				"project": 7,
				"rules": {
					"campaign": "2026-11",
					"rewards": [
						12
					]
				},
				"title": "November news"
			}
		}
	],
	"sendSupportMessage": [
		{
			"data": {
				"content": "I have a question about my project."
			},
			"project": "my-art"
		}
	],
	"transitionReward": [
		{
			"data": {
				"transition": "archive"
			},
			"project": "my-art",
			"reward": 7
		}
	],
	"unblockTipper": [
		{
			"relation": 7,
			"username": "ana"
		}
	],
	"unfollowThread": [
		{
			"threadToUser": 7
		}
	],
	"unlockThread": [
		{
			"threadToUser": 7
		}
	],
	"updateCampaign": [
		{
			"data": {
				"campaignName": "Art book",
				"campaignType": "per_project",
				"perProjectCampaign": {
					"campaignDeadlineDays": 30,
					"campaignDeadlineType": "days",
					"campaignGoal": 1000,
					"campaignGoalType": "amount"
				}
			},
			"project": "my-art"
		}
	],
	"updateGoal": [
		{
			"data": {
				"amount": 1200
			},
			"goal": 7,
			"project": "my-art"
		}
	],
	"updateNews": [
		{
			"data": {
				"draft": true,
				"name": "Updated studio news",
				"parameters": {
					"private_rule_rewards": [
						12
					],
					"private_type": "rewards"
				},
				"private": true
			},
			"news": 7,
			"project": "my-art"
		}
	],
	"updateProject": [
		{
			"data": {
				"tags": [
					{
						"name": "illustration"
					}
				],
				"translations": {
					"en": {
						"name": "My art studio"
					}
				}
			},
			"project": "my-art"
		}
	],
	"updateProjectAvatar": [
		{
			"data": {
				"avatar": {
					"uploadedFileOptions": {
						"height": 100,
						"width": 100,
						"x": 0,
						"y": 0
					}
				}
			},
			"files": {
				"avatar[uploadedFile]": {
					"contentType": "image/png",
					"filename": "avatar.png",
					"path": "upload.png"
				}
			},
			"project": "my-art"
		}
	],
	"updateProjectCover": [
		{
			"data": {
				"cover": {
					"uploadedFileOptions": {
						"height": 100,
						"width": 100,
						"x": 0,
						"y": 0
					}
				}
			},
			"files": {
				"cover[uploadedFile]": {
					"contentType": "image/png",
					"filename": "cover.png",
					"path": "upload.png"
				}
			},
			"project": "my-art"
		}
	],
	"updateProjectDescription": [
		{
			"data": {
				"translations": {
					"en": {
						"html": "\u003cp\u003eArt and illustration.\u003c/p\u003e"
					}
				}
			},
			"project": "my-art"
		}
	],
	"updateProjectLinks": [
		{
			"data": {
				"links": [
					{
						"code": "website",
						"value": "https://example.com"
					}
				]
			},
			"project": "my-art"
		}
	],
	"updateProjectSettings": [
		{
			"data": {
				"parameters": {
					"hidedAmount": {
						"value": 1
					}
				},
				"thanksMail": {
					"content": "Thank you for supporting my work."
				}
			},
			"project": "my-art"
		}
	],
	"updateReward": [
		{
			"data": {
				"modules": {
					"custom": {
						"settings": [
							{
								"name": "Size",
								"options": [
									{
										"is_additional_config": false,
										"name": "Small"
									}
								]
							}
						]
					}
				},
				"price": 12,
				"translations": {
					"en": {
						"description_v2": "\u003cp\u003eA new print each month.\u003c/p\u003e",
						"name": "Digital print"
					}
				}
			},
			"project": "my-art",
			"reward": 7
		}
	],
	"uploadMedia": [
		{
			"files": {
				"uploadedFile": {
					"contentType": "image/png",
					"filename": "art.png",
					"path": "upload.png"
				}
			},
			"isPrivate": false,
			"type": "image"
		}
	],
	"uploadMessageFileChunk": [
		{
			"data": {
				"chunkIndex": 0,
				"fileId": "123e4567-e89b-42d3-a456-426614174000",
				"fileName": "art.png",
				"totalChunks": 1
			},
			"files": {
				"file": {
					"contentType": "image/png",
					"filename": "art.png",
					"path": "upload.png"
				}
			}
		}
	]
}
]====])
