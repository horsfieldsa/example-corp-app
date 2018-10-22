class DetectModerationLabelsJob
    include SuckerPunch::Job
  
    def perform(sneaker_id)
        begin

            detection_logger.info("Attempting to detect moderation labels for Image: #{sneaker_id}")
            @sneaker = Sneaker.find(sneaker_id)

            config = {
                logger: xray_logger
              }
              
            XRay.recorder.configure(config)

            segment = XRay.recorder.begin_segment 'imagetrends'
            XRay.recorder.capture('detect_moderation_labels', segment: segment) do |subsegment|

                job_annotations = { 
                    image_id: @sneaker.id,
                    user_name: @sneaker.user.username,
                    user_id: @sneaker.user.id
                }
                subsegment.annotations.update job_annotations

                client = Aws::Rekognition::Client.new
                resp = client.detect_moderation_labels({
                        image: { bytes: @sneaker.sneaker_image.download }, 
                        min_confidence: 75,
                })

                if resp.moderation_labels.count == 0 
                    detection_logger.info("No moderation labels detected for Image: #{sneaker_id}")
                end           

                resp.moderation_labels.each do |label|
                    @tag = Tag.new
                    @tag.name = label.name
                    @tag.sneaker = @sneaker
                    @tag.confidence = label.confidence
                    @tag.source = "Rekognition - Detect Moderation Labels"               
                    @tag.save

                    if label.name == 'Suggestive' && label.confidence > 80
                        @sneaker.approved = false
                        @sneaker.save
                        detection_logger.warn("Inappropriate content detected, unapproving image #{sneaker_id}: #{@tag.name}")
                    end

                    detection_logger.info("Moderation label detected for Image: #{sneaker_id} Name: #{@tag.name} Confidence: #{@tag.confidence}")

                end
            
            end

            XRay.recorder.end_segment

            rescue StandardError => e
                puts("--------------------------------- [ERROR] ---------------------------------")
                puts(e)
                @tag = Tag.new
                @tag.name = "Error"
                @tag.source = "Rekognition - Detect Moderation Labels"
                @tag.sneaker = @sneaker
                @tag.save
                detection_logger.error("Error detecting moderation labels for Image: #{sneaker_id} Details: #{e}")
        end
    end

    def detection_logger
        @@detection_logger ||= Logger.new("#{Rails.root}/log/application.log")
    end

    def xray_logger
        @@xray_logger ||= Logger.new("#{Rails.root}/log/xray.log")
    end

end