import { Button, Frog, TextInput } from 'frog'
import { devtools } from 'frog/dev'
import { serveStatic } from 'frog/serve-static'
// import { GmonsterAbi } from '../constants/GmonsterAbi.js'
import { F1337Abi } from '../constants/F1337Abi.js'
// import { neynar } from 'frog/hubs'

export const app = new Frog({
  imageAspectRatio: '1:1'
})


app.frame('/', (c) => {
  return c.res({
    action: '/finish',
    image: 'https://gmon-frames.vercel.app/title.png',
    intents: [
      // <Button.Transaction target="/challenge">GM</Button.Transaction>,
      <Button action="/before-start">GM</Button>,
    ]
  })
})

app.frame('/finish', (c) => {
  const { transactionId } = c
  return c.res({
    image: 'https://gmon-frames.vercel.app/gmon/01.png', // TODO: Changed everyday
  })
})

app
.frame('/before-start', (c) => {
  return c.res({
    image: 'https://gmonster.vercel.app/before-start.png',
    intents: [
      <Button.Reset>Top</Button.Reset>,
      <Button.Link href="https://gmonster.vercel.app">Website</Button.Link>,
    ]
  })
})


app.transaction('/challenge', (c) => {
  return c.contract({
    abi: F1337Abi,
    chainId: 'eip155:8453', // TODO: To be changed. Base is eip155:8453, Base Sepolia is eip155:84532
    functionName: 'mint',
    to: '0x15EBaAD8717A6B71116ffAF1E0FD4A3b4DE0F96C' // F1337
  })
})
devtools(app, { serveStatic })

if (typeof Bun !== 'undefined') {
  Bun.serve({
    fetch: app.fetch,
    port: 3000,
  })
  console.log('Server is running on port 3000')
}
